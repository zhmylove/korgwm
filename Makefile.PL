#!/usr/bin/perl
use ExtUtils::MakeMaker;

my $repo = 'https://github.com/zhmylove/korgwm';

WriteMakefile(
    ABSTRACT        => q(a tiling window manager for X11),
    AUTHOR          => q(Sergei Zhmylev <zhmylove@narod.ru>),
    EXE_FILES       => [ "script/korgwm" ],
    LICENSE         => "mit",
    NAME            => "X11::korgwm",
    META_MERGE      => {
        dynamic_config  => 0,
        "meta-spec"     => { version => 2, url => "https://metacpan.org/pod/CPAN::Meta::Spec" },
        no_index        => { directory => [qw( t resources )] },
        release_status  => "stable",
        resources       => {
            bugtracker  => { web => "$repo/issues" },
            license     => [ "https://mit-license.org/" ],
            repository  => {
                type    => "git",
                url     => "$repo.git",
                web     => "$repo",
            },
        },
        x_authority     => "cpan:ZHMYLOVE",
        x_contributors  => [], # Feel free to add yourself here ;-)
    },
    PREREQ_PM       => {
        "AnyEvent"                      => "0",
        "AnyEvent::DBus"                => "0",
        "AnyEvent::Handle"              => "0",
        "AnyEvent::Socket"              => "0",
        "Carp"                          => "0",
        "Data::Dumper"                  => "0",
        "Encode"                        => "0",
        "Exporter"                      => "0",
        "Glib::Object::Introspection"   => "0",
        "Gtk3"                          => "0",
        "List::Util"                    => "0",
        "Net::DBus"                     => "0",
        "POSIX"                         => "0",
        "Scalar::Util"                  => "0",
        "Storable"                      => "0",
        "X11::XCB"                      => "0.24",
        "YAML::Tiny"                    => "0",
    },
    TEST_REQUIRES   => { "Test::More" => "0" },
    test => { TESTS => 't/*.t t/*/*.t' },
    VERSION_FROM    => "lib/X11/korgwm.pm",
);
