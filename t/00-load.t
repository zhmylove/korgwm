#!perl -T
use strict;
use warnings FATAL => 'all';
use Test::More;

my @modules = qw( Expose Panel Panel::Battery Panel::Clock Panel::Lang Xkb );
my @modules_nox = qw( API Common Config EWMH Hotkeys Layout Mouse Screen Tag Window );

if ($ENV{DISPLAY}) {
    plan tests => 1 + @modules + @modules_nox;
    use_ok("X11::korgwm");
    diag("Testing X11::korgwm $X11::korgwm::VERSION, Perl $], $^X");
    use_ok($_) for map { "X11::korgwm::$_" } @modules, @modules_nox;
} else {
    plan tests => 0 + @modules_nox;
    use_ok($_) for map { "X11::korgwm::$_" } @modules_nox;
}
