#!perl -T
use strict;
use warnings FATAL => 'all';
use Test::More;

my $XCB_VERSION = 0.23;
my @modules = qw( Expose Notifications Panel Panel::Battery Panel::Clock Panel::Lang Xkb );
my @modules_nox = qw( API Common Config EWMH Hotkeys Layout Mouse Screen Tag Window );
my @prerequisites = qw( AnyEvent AnyEvent::Handle AnyEvent::Socket Carp Encode Exporter Glib::Object::Introspection
    Gtk3 List::Util POSIX Scalar::Util Storable YAML::Tiny );

if ($ENV{DISPLAY}) {
    plan tests => 2 + @modules + @modules_nox + @prerequisites;
    use_ok("X11::korgwm");
    diag("Testing X11::korgwm $X11::korgwm::VERSION, Perl $], $^X");
    use_ok($_) for map { "X11::korgwm::$_" } @modules, @modules_nox;
} else {
    plan tests => 1 + @modules_nox + @prerequisites;
    use_ok($_) for map { "X11::korgwm::$_" } @modules_nox;
}

use_ok($_) or BAIL_OUT("Cannot use $_") for @prerequisites;
use_ok("X11::XCB", $XCB_VERSION) or BAIL_OUT("Cannot use X11::XCB >= $XCB_VERSION");
