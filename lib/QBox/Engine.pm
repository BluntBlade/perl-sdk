#!/usr/bin/env perl

# ============================================================================
# Name        : QBox::Engine
# Author      : Qiniu Developers
# Version     : 1.0.0.0
# Copyright   : 2012(c) Shanghai Qiniu Information Technologies Co., Ltd.
# Description : 
# ============================================================================

package QBox::Engine;

use strict;
use warnings;

use English;
use File::Basename;

use JSON;                            # external library
use Net::Curl::Easy qw(:constants);  # external library

use QBox::Base::Curl;
use QBox::Auth::Password;
use QBox::Auth::Token;
use QBox::Auth::Digest;
use QBox::Auth::UpToken;
use QBox::Auth::Policy;
use QBox::Client;
use QBox::RS;
use QBox::UP;
use QBox::EU;
use QBox::UC;
use QBox::Misc;
use QBox::ReaderAt::File;

my $pickup_param = sub {
    foreach my $p (@_) {
        if (defined($p)) {
            return $p;
        }
    } # foreach
    return undef;
};

my $get_svc = sub {
    my $self = shift;
    my $svc  = shift;
    if (not exists($self->{svc}{$svc})) {
        my $new_svc = lc("new_${svc}");
        $self->{svc}{$svc} = $self->$new_svc();
    }
    return $self->{svc}{$svc};
};

### rs methods
my $rs_pickup_args = sub {
    my $args = shift;
    my $rs_args = {
        file            => $pickup_param->($args->{file}, $args->{src}),
        bucket          => $pickup_param->($args->{bucket}, $args->{bkt}),
        key             => $pickup_param->($args->{key}),
        mime_type       => $pickup_param->($args->{mime_type}, $args->{mime}, 'application/octet-stream'),
        custom_meta     => $pickup_param->($args->{meta}),
        params          => $pickup_param->($args->{params}),
        callback_params => $pickup_param->($args->{callback_params}),

        attr            => $pickup_param->($args->{attr}),
        base            => $pickup_param->($args->{base}),
        domain          => $pickup_param->($args->{domain}),
    };

    $rs_args->{key} ||= (defined($rs_args->{file})) ? basename($rs_args->{file}) : undef;

    return $rs_args;
};

### up methods
sub resumable_put {
    my $self   = shift;
    my $args = shift;
    my $notify = $args->{notify} || {};
    my $opts   = shift || {};

    my $rs_args = $rs_pickup_args->($args);

    my $fsize     = (stat($rs_args->{file}))[7];
    my $reader_at = QBox::ReaderAt::File->new($rs_args->{file});

    $notify->{engine} = $self;

    my ($ret, $err, $prog) = ();
    if (defined($notify->{read_prog})) {
        $prog = $notify->{read_prog}->($notify);
    }

    $get_svc->($self, 'rs');
    ($ret, $err, $prog) = $self->{svc}{rs}->resumable_put(
        $prog,
        $notify->{blk_notify},
        $notify->{chk_notify},
        $notify,
        qbox_make_entry($rs_args->{bucket}, $rs_args->{key}),
        $rs_args->{mime_type},
        $reader_at,
        $fsize,
        $rs_args->{custom_meta},
        $rs_args->{params},
        $rs_args->{callback_params},
    );

    if ($err->{code} != 200) {
        if (defined($notify->{write_prog})) {
            $notify->{write_prog}->($notify, $prog);
        }
    }
    else {
        if (defined($notify->{end_prog})) {
            $notify->{end_prog}->($notify, $prog);
        }
    }

    return $ret, $err;
} # resumable_put

### eu methods
my $eu_gen_settings = sub {
    my $args   = shift;
    my $settings = shift || {};

    my $wms   = $pickup_param->($args->{wms});
    my $names = QBox::EU::wm_setting_names();

    if (defined($wms) and $wms ne q{}) {
        qbox_hash_merge($settings, qbox_json_load($wms), 'FROM', $names);
    }
    qbox_hash_merge($settings, $args, 'FROM', $names);

    return $settings;
};

my $exec = undef;
my $rs_exec = sub {
    my $self = shift;
    my $cmd  = shift;
    my $args = shift;
    $args = $rs_pickup_args->($args);
    return $exec->($self, 'rs', $cmd, $args, @_);
};

my %methods = (
    'auth'          => '',
    'access_key'    => 'auth',
    'secret_key'    => 'auth',
    'client_id'     => 'auth',
    'client_secret' => 'auth',
    'username'      => 'auth',
    'password'      => 'auth',
    'policy'        => 'auth',

    'hosts'         => '',
    'ac_host'       => 'hosts',
    'io_host'       => 'hosts',
    'up_host'       => 'hosts',
    'rs_host'       => 'hosts',
    'uc_host'       => 'hosts',
    'eu_host'       => 'hosts',

    'get'           => sub { my $self = shift; return $rs_exec->($self, 'get', @_); },
    'stat'          => sub { my $self = shift; return $rs_exec->($self, 'stat', @_); },
    'publish'       => sub { my $self = shift; return $rs_exec->($self, 'publish', @_); },
    'unpublish'     => sub { my $self = shift; return $rs_exec->($self, 'unpublish', @_); },
    'put_auth'      => sub { my $self = shift; return $rs_exec->($self, 'put_auth', @_); },
    'put_file'      => sub { my $self = shift; return $rs_exec->($self, 'put_file', @_); },
    'delete'        => sub { my $self = shift; return $rs_exec->($self, 'delete', @_); },
    'drop'          => sub { my $self = shift; return $rs_exec->($self, 'drop', @_); },
    'query'         => sub { my $self = shift; return $exec->($self, 'up', 'query', @_); },
    'wmget'         => sub { my $self = shift; return $exec->($self, 'eu', 'wmget', @_); },
    'wmset'         => sub { my $self = shift; return $exec->($self, 'eu', 'wmset', @_); },
    'app_info'      => sub { my $self = shift; return $exec->($self, 'uc', 'app_info', @_); },
    'new_access'    => sub { my $self = shift; return $exec->($self, 'uc', 'new_access', @_); },
    'delete_access' => sub { my $self = shift; return $exec->($self, 'uc', 'delete_access', @_); },
);

# make aliases
$methods{pub}   = $methods{publish};
$methods{unpub} = $methods{unpublish};
$methods{puta}  = $methods{put_auth};
$methods{putaf} = sub { return &put_auth_file; };
$methods{putf}  = $methods{put_file};
$methods{rput}  = sub { return &resumable_put; };
$methods{del}   = $methods{delete};
$methods{appi}  = $methods{app_info};
$methods{nacs}  = $methods{new_access};
$methods{dacs}  = $methods{delete_access};

$exec = sub {
    my $self = shift;
    my $svc  = shift;
    my $cmd  = shift;
    my $args = shift;
    my $opts = shift || {};

    $get_svc->($self, $svc);

    my $svc_host = $self->{svc}{$svc};
    return $svc_host->$cmd($args, $opts);
};

our $AUTOLOAD;
sub AUTOLOAD {
    my $nm = $AUTOLOAD;
    $nm =~ s/^.+://;

    if (not exists($methods{$nm})) {
        return undef, {
            'code'    => 499,
            'message' => "No such command.(cmd=${nm})",
        };
    }

    my $method = undef;
    my $sub = $methods{$nm};
    if (ref($sub) eq 'CODE') {
        $method = $sub;
    }
    elsif ($sub eq q{}) {
        $method = sub {
            my ($self, $new) = @_;
            my $old = $self->{$nm};
            if (defined($new)) {
                $self->{$nm} = $new;
            }
            return $old;
        };
    }
    elsif ($sub ne q{}) {
        $method = sub {
            my ($self, $new) = @_;
            $self->{$sub} ||= {};
            my $old = $self->{$sub}{$nm};
            if (defined($new)) {
                $self->{$sub}{$nm} = $new;
            }
            return $old;
        };
    }

    if (defined($method)) {
        no strict;
        #*$QBox::Engine::{$nm}{CODE} = $method;
        *$AUTOLOAD = $method;
        use strict;

        goto &$AUTOLOAD;
    }
} # AUTOLOAD

sub wmmod {
    my $self   = shift;
    my $args = shift;

    my ($settings, $err) = $self->wmget($args);
    if ($err->{code} != 200) {
        return undef, $err;
    }

    $settings = $eu_gen_settings->($args, $settings);
    return $self->wmset($settings);
} # wmmod

sub put_auth_file {
    my $self   = shift;
    my $args = shift;

    my ($ret, $err) = $self->put_auth_ex($args);
    return $ret, $err if ($err->{code} != 200);

    my $rs_args = $rs_pickup_args->($args);
    my $entry   = qbox_make_entry($rs_args->{bucket}, $rs_args->{key});
    my $mime    = $pickup_param->($rs_args->{mime}, 'application/octet-stream');

    $entry      = qbox_base64_encode_urlsafe($entry);
    $mime       = qbox_base64_encode_urlsafe($mime);

    my $body = {
        action => "/rs-put/${entry}/mimeType/${mime}",
        params => $pickup_param->($rs_args->{params}, q{}),
    };
    
    my $file_body = {
        file => $rs_args->{file},
    };

    my $form = qbox_curl_make_multipart_form($body, $file_body);
    my $curl = qbox_curl_call_pre(
        $ret->{url},
        undef,
        { 'api' => 'rs.put-auth-file' }
    );
    $curl->setopt(CURLOPT_HTTPPOST, $form);
    return qbox_curl_call_core($curl);
} # put_auth_file

### init methods
sub new {
    my $class = shift || __PACKAGE__;
    my $self  = {
        'svc'   => {},
        'hosts' => {},
        'auth'  => {
            'username'   => undef,
            'password'   => undef,
            'access_key' => undef,
            'secret_key' => undef,
        },
        'out_fh' => undef,
    };
    return bless $self, $class;
} # new

### helper methods
sub new_up {
    my $self = shift;
    return QBox::UP->new($self->{client}, $self->{hosts});
} # new_up

sub new_rs {
    my $self = shift;
    return QBox::RS->new($self->{client}, $self->{hosts});
} # new_rs

sub new_uc {
    my $self = shift;
    return QBox::UC->new($self->{client}, $self->{hosts});
} # new_uc

sub new_eu {
    my $self = shift;
    return QBox::EU->new($self->{client}, $self->{hosts});
} # new_eu

sub set_host {
    my $self  = shift;
    my $hosts = shift;
    my $value = shift;

    if (ref($hosts) eq 'HASH') {
        qbox_hash_merge($self->{hosts}, $hosts, 'FROM');
    }

    return {}, { 'code' => 200, 'message' => 'Host info set' };
} # set_host

sub unset_host {
    my $self  = shift;
    my $hosts = shift;

    if (ref($hosts) eq 'HASH') {
        map { delete($self->{hosts}{$_}) } keys(%$hosts);
    }
    elsif (ref($hosts) eq q{}) {
        undef($self->{hosts}{$hosts});
    }

    return {}, { 'code' => 200, 'message' => 'Host info unset' };
} # unset_host

sub set_auth {
    my $self = shift;
    my $auth = shift;

    if (ref($auth) eq 'HASH') {
        qbox_hash_merge($self->{auth}, $auth, 'TO');
    }

    return {}, { 'code' => 200, 'message' => 'Auth info set'};
} # set_host

sub unset_auth {
    my $self = shift;
    my $auth = shift;

    if (ref($auth) eq 'HASH') {
        map { delete($self->{auth}{$_}) } keys(%$auth);
    }
    elsif (ref($auth) eq q{}) {
        undef($self->{auth}{$auth});
    }

    return {}, { 'code' => 200, 'message' => 'Auth info unset'};
} # unset_host

sub auth_by_password {
    my $self = shift;
    my $args = shift;

    my $username = $pickup_param->($args->{username}, $self->{auth}{username});
    my $password = $pickup_param->($args->{password}, $self->{auth}{password});

    if (defined($username) and defined($password)) {
        my $client_id     = $self->{auth}{client_id};
        my $client_secret = $self->{auth}{client_secret};

        my $token = QBox::Auth::Token->new($self->{hosts}, $client_id, $client_secret);
        my $auth  = QBox::Auth::Password->new($token, $username, $password);

        eval {
            my $new_client = QBox::Client->new($auth);

            if ($self->{client}) {
                undef $self->{client};
            }

            $self->{client} = $new_client;
            return {}, { 'code' => 200, 'message' => 'Login by password'};
        };

        if ($EVAL_ERROR) {
            return undef, { 'code' => 499, 'message' => "$EVAL_ERROR" };
        }
    }

    return undef, { 'code' => 499, 'message' => "No username or password" };
} # auth_by_password

sub auth_by_access_key {
    my $self = shift;
    my $args = shift;

    my $acs_key = $pickup_param->($args->{access_key}, $self->{auth}{access_key}, 'Put your ACCESS KEY here');
    my $scr_key = $pickup_param->($args->{secret_key}, $self->{auth}{secret_key}, 'Put your SECRET KEY here');
    my $policy  = $pickup_param->($args->{policy}, $self->{auth}{policy});

    if (not defined($acs_key) or not defined($scr_key)) {
        return undef, { 'code' => 499, 'message' => "No access key or secret key." };
    }

    my $new_client = undef;
    eval {
        if (defined($policy) and $policy ne q{}) {
            $policy = ref($policy) eq q{} ? from_json($policy) : $policy;
            $policy = QBox::Auth::Policy->new($policy);
            my $auth = QBox::Auth::UpToken->new($acs_key, $scr_key, $policy);
            $new_client = QBox::Client->new($auth);
        }
        else {
            my $auth = QBox::Auth::Digest->new($acs_key, $scr_key);
            $new_client = QBox::Client->new($auth);
        }
    };

    if ($EVAL_ERROR) {
        return undef, { 'code' => 499, 'message' => "$EVAL_ERROR" };
    }

    if ($self->{client}) {
        undef $self->{client};
    }

    $self->{client} = $new_client;
    return {}, { 'code' => 200, 'message' => 'Login by access key'};
} # auth_by_access_key

sub auto_auth {
    my $self = shift;
    my ($ret, $err) = ();

    ($ret, $err) = $self->auth_by_password();
    return $ret, $err if $ret;

    ($ret, $err) = $self->auth_by_access_key();
    return $ret, $err;
} # auto_auth

sub set_header {
    my $self    = shift;
    my $headers = shift;
    my $value   = shift;

    if (ref($headers) eq 'HASH') {
        qbox_hash_merge($self->{headers}, $headers, 'FROM');
    }
    elsif (ref($headers) eq q{}) {
        $self->{headers}{$headers} = $value;
    }

    return {}, { 'code' => 200, 'message' => 'Header info set' };
} # set_header

sub unset_header {
    my $self  = shift;
    my $headers = shift;

    if (ref($headers) eq 'HASH') {
        map { delete($self->{headers}{$_}) } keys(%$headers);
    }
    elsif (ref($headers) eq q{}) {
        undef($self->{headers}{$headers});
    }

    return {}, { 'code' => 200, 'message' => 'Header info unset' };
} # unset_header

1;

__END__
