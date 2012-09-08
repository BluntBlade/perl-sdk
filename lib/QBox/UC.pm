#!/usr/bin/env perl

# ============================================================================
# Name        : QBox::UC
# Author      : Qiniu Developers
# Version     : 1.0.0.0
# Copyright   : 2012(c) Shanghai Qiniu Information Technologies Co., Ltd.
# Description : 
# ============================================================================

package QBox::UC;

use strict;
use warnings;

use QBox::Config;

use constant API_APP_INFO      => 'uc.app-info';
use constant API_NEW_ACCESS    => 'uc.new-access';
use constant API_DELETE_ACCESS => 'uc.delete-access';

sub new {
    my $class = shift || __PACKAGE__;
    my $client = shift;
    my $hosts  = shift || {};

    $hosts->{uc_host} ||= QBox::Config::QBOX_UC_HOST;

    my $self = {
        client => $client,
        hosts  => $hosts,
    };
    return bless $self, $class;
} # new

sub app_info {
    my $self = shift;
    my $app  = shift;

    my $query = { app => $app };

    my $url = "$self->{hosts}{uc_host}/appInfo";
    return $self->{client}->call_with_form(
        $url,
        $query,
        undef,  # no body length
        { 'api' => API_APP_INFO }
    );
} # app_info

sub new_access {
    my $self = shift;
    my $app  = shift;

    my $query = { app => $app };

    my $url = "$self->{hosts}{uc_host}/newAccess";
    return $self->{client}->call_with_form(
        $url,
        $query,
        undef,
        { 'api' => API_NEW_ACCESS }
    );
} # new_access

sub delete_access {
    my $self    = shift;
    my $app     = shift;
    my $acs_key = shift;

    my $query = { app => $app, key => $acs_key };

    my $url = "$self->{hosts}{uc_host}/deleteAccess";
    return $self->{client}->call_with_form(
        $url,
        $query,
        undef,
        { 'api' => API_DELETE_ACCESS }
    );
} # delete_access

1;

__END__
