#!/usr/bin/perl

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

use strict;
use warnings;
use utf8;
use Test::More tests => 82;
use Test::Deep;
use lib qw{.. ../lib ../../lib};
use Test::MockModule;
use Data::Dumper;
use TestUtils;




sub assert_filters($$@)
{
	my ($msg, $queryref, @parsed) = @_;
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			my $res = config_create_and_parse(@$queryref);
			ok !($res->{errors}||$res->{warnings}), $msg;
			is scalar (my @got = @{$res->{options}{filters}{parsed}}), scalar @parsed;
			print Dumper \@got;
			while (@parsed) {
				my $got = shift @got;
				my $expected = shift @parsed;
				print Dumper $got;
				cmp_deeply $got, superhashof $expected;
			}
		}
	}
}

# include

assert_filters "include should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a --include *.gz!],
	{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)};

assert_filters "two includes should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a --include *.gz --include *.txt!],
	{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '+', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)};

# exclude

assert_filters "exclude should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a --exclude *.gz!],
	{ action => '-', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)};

assert_filters "two excludes should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a --exclude *.gz --exclude *.txt!],
	{ action => '-', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)},
	;
# filter

assert_filters "filter should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a --filter!, '+*.gz'],
	{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)};

assert_filters "double filter should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a --filter!, '+*.gz -*.txt'],
	{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)},
	;
assert_filters "two filters should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a!, '--filter', '+*.gz', '--filter', '-*.txt'],
	{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)};

assert_filters "filter + double filter should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a!, '--filter', '+*.gz', '--filter', '-*.txt +*.jpeg'],
	{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '+', pattern => '*.jpeg', notmatch => bool(0), match_subdirs => bool(0)};

# include, exclude, filter

assert_filters "filter and include should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a!, '--filter', '+*.gz', '--include', '*.txt'],
	{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '+', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)}
	;

assert_filters "filter and exclude should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a!, '--filter', '+*.gz', '--exclude', '*.txt'],
	{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)}
	;
assert_filters "filter + double filter + include + exclude should work",
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a!,
	'--filter', '+*.gz', '--filter', '-*.txt +*.jpeg', '--include', 'dir/', '--exclude', 'dir2/'],
	{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '+', pattern => '*.jpeg', notmatch => bool(0), match_subdirs => bool(0)},
	{ action => '+', pattern => 'dir/', notmatch => bool(0), match_subdirs => bool(1)},
	{ action => '-', pattern => 'dir2/', notmatch => bool(0), match_subdirs => bool(1)};

1;