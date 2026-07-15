package Digest::TestBytes;

# Test fixture that records raw bytes passed to add().
# Used to verify that Digest properly encodes UTF-8 strings.

use strict;
use warnings;

our @ISA = qw(Digest::base);

require Digest::base;

sub new {
    my $class = shift;
    bless { data => '' }, $class;
}

sub add {
    my $self = shift;
    $self->{data} .= join( '', @_ );
    return $self;
}

sub digest {
    my $self = shift;
    my $d    = $self->{data};
    $self->{data} = '';
    return $d;
}

1;
