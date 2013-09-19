# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

package App::MtAws::QueueJob::Iterator;

our $VERSION = '1.051';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;

	$self->{iterator}||confess;
	$self->{jobs} = {};
	$self->{pending} = {};
	$self->{task_autoincrement} = $self->{job_autoincrement} = 0;
	$self->enter('itt_only');
}


sub get_next_itt
{
	my ($self) = @_;
	my $next_job = $self->{iterator}->();
	if ($next_job) {
		my $i = ++$self->{job_autoincrement};
		$self->{jobs}{$i} = $next_job;
	}
	$next_job;
}

sub find_next_job
{
	my ($self) = @_;
	my $maxcnt = $self->{maxcnt}||30;
	for my $job_id (keys %{$self->{jobs}}) {
		my $job = $self->{jobs}{$job_id};
		my $res = $job->next();
		if ($res->{code} eq JOB_WAIT) {
			if ($self->{one_by_one}) {
				return JOB_WAIT;
			} else {
				return JOB_WAIT unless --$maxcnt;
			}
		} elsif ($res->{code} eq JOB_DONE) {
			delete $self->{jobs}{$job_id};
			return JOB_RETRY;
		} elsif ($res->{code} eq JOB_OK) {
			my $task_id = ++$self->{task_autoincrement};
			$self->{pending}{$task_id} = 1;
			return task($res->{task}, sub {
				delete $self->{pending}{$task_id} or confess;
				delete $self->{jobs}{$job_id} or confess;
				$res->{task}{cb_task_proxy}->();
				return;
			});
		} else {
			confess;
		}
	}
	return;
}

# there are no pending jobs, only iterator available
sub on_itt_only
{
	my ($self) = @_;

	if ($self->get_next_itt) {
		return state 'itt_and_jobs'; # immediatelly switch to other state
	} else {
		return JOB_DONE;
	}
}


# both jobs and iterator available
sub on_itt_and_jobs
{
	my ($self) = @_;
	my $maxcnt = $self->{maxcnt}||30;
	if (my @r = find_next_job) { # try to process one pending job
		return @r;
	} elsif ($self->get_next_itt) {
		return JOB_RETRY # otherwise, get new job from iteartor and retry
	} else {
		return state 'jobs_only' # no jobs in iterator? - switch to jobs_only
	}
}

sub on_jobs_only
{
	my ($self) = @_;
	if (my @r = $self->find_next_job) {
		return @r; # can be 'wait' here
	} else {
		return keys %{$self->{jobs}} ? JOB_WAIT : state "done";
	}
}

1;