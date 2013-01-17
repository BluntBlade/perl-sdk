#!/usr/bin/env perl

# ============================================================================
# Name        : QBox::XLog
# Author      : Qiniu Developers
# Version     : 1.0.0.0
# Copyright   : 2013(c) Shanghai Qiniu Information Technologies Co., Ltd.
# Description : 
# ============================================================================

package QBox::XLog;

use strict;
use warnings;

use English;
use Time::HiRes;

use QBox::Misc;

use constant QBOX_MSG_DEBUG => 1;
use constant QBOX_MSG_INFO  => 2;
use constant QBOX_MSG_WARN  => 3;
use constant QBOX_MSG_ERROR => 4;
use constant QBOX_MSG_FATAL => 5;

use constant QBOX_MSG_FMT   => '%s %s [%s] %s';

my %level_map = (
    +QBOX_MSG_DEBUG => 'DEBUG',
    +QBOX_MSG_INFO  => 'INFO',
    +QBOX_MSG_WARN  => 'WARN',
    +QBOX_MSG_ERROR => 'ERROR',
    +QBOX_MSG_FATAL => 'FATAL',
);

my $gen_timestamp = sub {
    my ($seconds, $mseconds) = gettimeofday();
    my ($sec, $min, $hour, $day, $month, $year) = localtime($seconds);
    return sprintf(
        "%04d-%02d-%02d %02d:%02d:%02d.%03d",
        $year + 1900,
        $month + 1,
        $day,
        $hour,
        $min,
        $sec,
        substr("$mseconds", 0, 3)
    );
};

sub new {
    my $class = shift || __PACKAGE__;
    my $self  = {
        req_id => shift,
        msg    => [],
    };

    if (not defined($self->{req_id})) {
        my $id_str = sprintf("${PID}%s%s", gettimeofday());
        $self->{req_id} = qbox_base64_encode_urlsafe($id_str);
    }

    return bless $class, $self;
} # new

sub marshal {
    my $self = shift;
    return join "\n", @{$self->{msg}};
} # marshal

sub req_id {
    my $self = shift;
    return $self->{seq_id};
} # req_id

sub log {
    my $self  = shift;
    my $level = shift;
    $level = $level_map{$level} || $level;
    my $ts = $gen_timestamp->();
    push @{$self->{msg}}, sprintf(QBOX_MSG_FMT, $ts, $self->{req_id}, $level, "@_");
} # log

sub debug {
    my $self  = shift;
    return $self->log(QBOX_MSG_DEBUG, @_);
} # debug

sub info {
    my $self  = shift;
    return $self->log(QBOX_MSG_INFO, @_);
} # info 

sub warn {
    my $self  = shift;
    return $self->log(QBOX_MSG_WARN, @_);
} # warn

sub error {
    my $self  = shift;
    return $self->log(QBOX_MSG_ERROR, @_);
} # error

sub fatal {
    my $self  = shift;
    return $self->log(QBOX_MSG_FATAL, @_);
} # fatal

1;

__END__
