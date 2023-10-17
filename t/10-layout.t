#!perl -T
use strict;
use warnings FATAL => 'all';
no warnings 'experimental::signatures';
use feature 'signatures';
use Test::More;

use X11::korgwm::Common;
use X11::korgwm::Layout;

my $results;
my $expected = [
    [0, 0, 16, 12, undef],
    [0, 0, 8, 12, undef],
    [8, 0, 8, 12, undef],
    [0, 0, 8, 12, undef],
    [8, 0, 8, 6, undef],
    [8, 6, 8, 6, undef],
    [0, 0, 8, 6, undef],
    [0, 6, 8, 6, undef],
    [8, 0, 8, 6, undef],
    [8, 6, 8, 6, undef],
    [0, 0, 8, 6, undef],
    [0, 6, 8, 6, undef],
    [8, 0, 8, 4, undef],
    [8, 4, 8, 4, undef],
    [8, 8, 8, 4, undef],
    [0, 0, 6, 6, undef],
    [0, 6, 6, 6, undef],
    [6, 0, 5, 6, undef],
    [6, 6, 5, 6, undef],
    [11, 0, 5, 6, undef],
    [11, 6, 5, 6, undef],
    [0, 0, 6, 6, undef],
    [0, 6, 6, 6, undef],
    [6, 0, 5, 6, undef],
    [6, 6, 5, 6, undef],
    [11, 0, 5, 4, undef],
    [11, 4, 5, 4, undef],
    [11, 8, 5, 4, undef],
    [0, 0, 6, 6, undef],
    [0, 6, 6, 6, undef],
    [6, 0, 5, 4, undef],
    [6, 4, 5, 4, undef],
    [6, 8, 5, 4, undef],
    [11, 0, 5, 4, undef],
    [11, 4, 5, 4, undef],
    [11, 8, 5, 4, undef],
    [0, 0, 6, 4, undef],
    [0, 4, 6, 4, undef],
    [0, 8, 6, 4, undef],
    [6, 0, 5, 4, undef],
    [6, 4, 5, 4, undef],
    [6, 8, 5, 4, undef],
    [11, 0, 5, 4, undef],
    [11, 4, 5, 4, undef],
    [11, 8, 5, 4, undef],
    [0, 0, 4, 6, undef],
    [0, 6, 4, 6, undef],
    [4, 0, 4, 6, undef],
    [4, 6, 4, 6, undef],
    [8, 0, 4, 4, undef],
    [8, 4, 4, 4, undef],
    [8, 8, 4, 4, undef],
    [12, 0, 4, 4, undef],
    [12, 4, 4, 4, undef],
    [12, 8, 4, 4, undef],
    [0, 0, 4, 6, undef],
    [0, 6, 4, 6, undef],
    [4, 0, 4, 4, undef],
    [4, 4, 4, 4, undef],
    [4, 8, 4, 4, undef],
    [8, 0, 4, 4, undef],
    [8, 4, 4, 4, undef],
    [8, 8, 4, 4, undef],
    [12, 0, 4, 4, undef],
    [12, 4, 4, 4, undef],
    [12, 8, 4, 4, undef],
    [0, 0, 4, 4, undef],
    [0, 4, 4, 4, undef],
    [0, 8, 4, 4, undef],
    [4, 0, 4, 4, undef],
    [4, 4, 4, 4, undef],
    [4, 8, 4, 4, undef],
    [8, 0, 4, 4, undef],
    [8, 4, 4, 4, undef],
    [8, 8, 4, 4, undef],
    [12, 0, 4, 4, undef],
    [12, 4, 4, 4, undef],
    [12, 8, 4, 4, undef],
    [0, 0, 16, 12, 0]
];

{
    package Mock::X11;
    sub flush { 1 }
}

{
    package Mock::Window;
    my $i = 0;
    sub new($class) { my $id = $i++; bless { id => $id }, $class }
    sub resize_and_move($self, $x, $y, $w, $h, $hide=undef) {
        $results->[$self->{id}] = [$x, $y, $w, $h, $hide];
    }
}

$X = bless {}, "Mock::X11";

my $l = X11::korgwm::Layout->new();
isnt(eval { $l->arrange_windows({}, 16, 12); 1}, 1, "Croak on invalid input");
is($l->arrange_windows([], 16, 12), undef, "Nothing on no windows");

# Test in different combinations
$l->arrange_windows([map {Mock::Window->new()} 1..$_], 16, 12) for 1..12;

# Test on hide border
push @screens, undef;
$l->arrange_windows([Mock::Window->new()], 16, 12);

is_deeply($results, $expected, "Layout for multiple windows");
done_testing();
