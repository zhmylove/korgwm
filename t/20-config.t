#!perl -T
use strict;
use warnings FATAL => 'all';
no warnings 'experimental::signatures';
use feature 'signatures';
use Test::More;

BEGIN { $ENV{KORGWM_DEBUG_CONFIG} = "" }

use X11::korgwm::Config;
use X11::korgwm::Common;
use YAML::Tiny;

# Verify that sample matches the default config
my $sample = YAML::Tiny->read("korgwm.conf.sample");
ref($sample) eq "YAML::Tiny" and $sample = $sample->[0];

is_deeply($sample, $X11::korgwm::Config::debug_config, "korgwm.conf.sample matches the default config");

done_testing();
