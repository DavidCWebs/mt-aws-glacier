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

package App::MtAws::SyncCommand;

use strict;
use warnings;
use utf8;
use Carp;
use constant ONE_MB => 1024*1024;
use App::MtAws::JobProxy;
use App::MtAws::JobListProxy;
use App::MtAws::JobIteratorProxy;
use App::MtAws::FileCreateJob;
use App::MtAws::FileListDeleteJob;
use App::MtAws::FileVerifyAndUploadJob;
use App::MtAws::ForkEngine  qw/with_forks fork_engine/;
use App::MtAws::Journal;
use App::MtAws::Utils;



sub is_mtime_differes
{
	my ($options, $journal_file, $absfilename) = @_;
	my $mtime_differs = $options->{detect} =~ /(^|[-_])mtime([-_]|$)/ ? # don't make stat() call if we don't need it
		defined($journal_file->{mtime}) && file_mtime($absfilename) != $journal_file->{mtime} :
		undef;
}

sub next_modified
{
	my ($options, $j) = @_;
	while (my $rec = shift @{ $j->{listing}{existing} }) {
		my $relfilename = $rec->{relfilename};
		my $absfilename = $j->absfilename($relfilename);
		my $file = $j->latest($relfilename);
		
		my $should_upload = 0;
		
		my $mtime_differs = is_mtime_differes($options, $file, $absfilename);
		
		if ($file->{size} != file_size($absfilename)) {
			$should_upload = 'create';
		} elsif ($options->{detect} eq 'mtime') {
			$should_upload = $mtime_differs ? 'create' : 0;
		} elsif ($options->{detect} eq 'treehash') {
			$should_upload = 'treehash';
		} elsif ($options->{detect} eq 'mtime-and-treehash') {
			$should_upload = $mtime_differs ? 'treehash' : 0;
		} elsif ($options->{detect} eq 'mtime-or-treehash') {
			$should_upload = $mtime_differs ? 'create' : 'treehash';
		} else {
			confess;
		}
		if ($should_upload eq 'treehash') {
			return App::MtAws::JobProxy->new(job=>
				App::MtAws::FileVerifyAndUploadJob->new(filename => $absfilename,
					relfilename => $relfilename, partsize => ONE_MB*$options->{partsize},
					delete_after_upload => 1,
					archive_id => $file->{archive_id},
					treehash => $file->{treehash}
			));
		} elsif ($should_upload eq 'create') {
			return App::MtAws::JobProxy->new(job=> App::MtAws::FileCreateJob->new(
				filename => $absfilename, relfilename => $relfilename, partsize => ONE_MB*$options->{partsize},
				(finish_cb => sub {
					App::MtAws::FileListDeleteJob->new(archives => [{
						archive_id => $file->{archive_id}, relfilename => $relfilename
					}])
				})
			));
		} elsif (!$should_upload) {
			next;
		} else {
			confess;
		}
	}
	return;
}

sub next_missing
{
	my ($options, $j) = @_;
	if (my $rec = shift @{ $j->{listing}{missing} }) {
		App::MtAws::FileListDeleteJob->new(archives => [{
			archive_id => $j->latest($rec->{relfilename})->{archive_id}, relfilename => $rec->{relfilename}
		}]);
	} else {
		return;
	}
}

sub next_new
{
	my ($options, $j) = @_;
	if (my $rec = shift @{ $j->{listing}{new} }) {
		my ($absfilename, $relfilename) = ($j->absfilename($rec->{relfilename}), $rec->{relfilename});
		App::MtAws::JobProxy->new(job =>
				App::MtAws::FileCreateJob->new(filename => $absfilename, relfilename => $relfilename, partsize => ONE_MB*$options->{partsize}));
	} else {
		return;
	}
}

sub print_dry_run
{
	my ($itt) = @_;
	while (my $rec = $itt->()) {
		for ($rec->will_do()) {
			print $_."\n";
		}
	}
}

sub run
{
	my ($options, $j) = @_;
	with_forks !$options->{'dry-run'}, $options, sub {
		$j->read_journal(should_exist => 0); # TODO: what about case when --new is missing?
		
		my $read_journal_opts = {
			$options->{'new'} ? ('new' => 1) : (),
			$options->{'replace-modified'} ? ('existing' => 1) : (),
			$options->{'delete-removed'} ? ('missing' => 1) : (),
		};
		
		$j->read_files($read_journal_opts, $options->{'max-number-of-files'}); # TODO: sometimes read only 'new' files
		
		$j->open_for_write();
		my @joblist;
		
		if ($options->{new}) {
			my $itt = sub { next_new($options, $j) };
			if ($options->{'dry-run'}) {
				print_dry_run($itt);
			} else {
				push @joblist, App::MtAws::JobIteratorProxy->new(iterator => $itt);
			}
		}

		if ($options->{'replace-modified'}) {
			confess unless $options->{detect};
			my $itt = sub { next_modified($options, $j) };
			if ($options->{'dry-run'}) {
				print_dry_run($itt);
			} else {
				push @joblist, App::MtAws::JobIteratorProxy->new(iterator => $itt);
			}
		}
		if ($options->{'delete-removed'}) {
			my $itt = sub { next_missing($options, $j) };
			if ($options->{'dry-run'}) {
				print_dry_run($itt);
			} else {
				push @joblist, App::MtAws::JobIteratorProxy->new(iterator => $itt);
			}
		}

		if (scalar @joblist) {
			my $lt = App::MtAws::JobListProxy->new(jobs => \@joblist);
			my ($R) = fork_engine->{parent_worker}->process_task($lt, $j);
			die unless $R;
		}
		$j->close_for_write();
	}
}


1;

__END__
