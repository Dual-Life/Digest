#!/usr/bin/env perl

# Tests for Digest->new() dispatch logic:
# - MMAP lookup with single module, array fallbacks, and arrayrefs with args
# - AUTOLOAD dispatch (Digest->Algorithm sugar)
# - Non-word character stripping for unmapped algorithms
# - Error propagation when all implementations fail
# - $@ preservation for callers

use strict;
use warnings;

use Test::More tests => 16;

use lib 't/lib';
use Digest;

# --- Setup mock modules in-memory so we don't need files on disk ---

# A simple mock that records what args it received
{
    package Digest::MockA;
    our $VERSION = 1;
    sub new {
        my $class = shift;
        bless { class => $class, args => [@_] }, $class;
    }
}

{
    package Digest::MockB;
    our $VERSION = 1;
    sub new {
        my $class = shift;
        bless { class => $class, args => [@_] }, $class;
    }
}

# --- Test 1: Direct MMAP hit with a plain string ---
{
    local %Digest::MMAP = ( 'TEST-A' => 'Digest::MockA' );
    my $obj = Digest->new('TEST-A');
    isa_ok( $obj, 'Digest::MockA', 'MMAP string entry dispatches correctly' );
}

# --- Test 2: MMAP hit with arrayref containing [class, args] ---
{
    local %Digest::MMAP = ( 'TEST-B' => [ ['Digest::MockA', 42, 'extra'] ] );
    my $obj = Digest->new('TEST-B');
    isa_ok( $obj, 'Digest::MockA', 'MMAP arrayref with args dispatches correctly' );
    is_deeply( $obj->{args}, [42, 'extra'], 'MMAP args are passed to constructor' );
}

# --- Test 3: MMAP fallback chain — first fails, second succeeds ---
{
    local %Digest::MMAP = (
        'TEST-FALLBACK' => [ 'Digest::NoSuchModule', 'Digest::MockB' ]
    );
    my $obj = Digest->new('TEST-FALLBACK');
    isa_ok( $obj, 'Digest::MockB', 'Falls back to second module when first is not loaded' );
}

# --- Test 4: MMAP fallback chain with arrayrefs ---
{
    local %Digest::MMAP = (
        'TEST-CHAIN' => [
            ['Digest::NoSuchModule', 1],
            ['Digest::MockA', 99],
        ]
    );
    my $obj = Digest->new('TEST-CHAIN');
    isa_ok( $obj, 'Digest::MockA', 'Arrayref fallback chain works' );
    is_deeply( $obj->{args}, [99], 'Correct args from fallback entry' );
}

# --- Test 5: Unmapped algorithm — non-word chars stripped, Digest:: prepended ---
{
    # Digest::MockA is already loaded, so Digest->new("Mock-A") should find it
    # "Mock-A" is not in MMAP, so it strips "-" and tries Digest::MockA
    my $obj = Digest->new('Mock-A');
    isa_ok( $obj, 'Digest::MockA', 'Unmapped algorithm strips non-word chars' );
}

# --- Test 6: AUTOLOAD sugar — Digest->MockB(...) ---
{
    my $obj = Digest->MockB('arg1');
    isa_ok( $obj, 'Digest::MockB', 'AUTOLOAD dispatch works' );
    is_deeply( $obj->{args}, ['arg1'], 'AUTOLOAD passes arguments through' );
}

# --- Test 7: All implementations fail — dies with the first error ---
{
    local %Digest::MMAP = (
        'TEST-FAIL' => [ 'Digest::Nonexistent1', 'Digest::Nonexistent2' ]
    );
    eval { Digest->new('TEST-FAIL') };
    like( $@, qr/Can't locate Digest\/Nonexistent1\.pm/,
        'Dies with the FIRST error when all implementations fail' );
}

# --- Test 8: Caller's $@ is preserved on success ---
{
    $@ = "caller_error_sentinel";
    my $obj = Digest->new('MockA');
    is( $@, "caller_error_sentinel", '$@ is preserved after successful new()' );
}

# --- Test 9: Extra args from caller are appended after MMAP args ---
{
    local %Digest::MMAP = ( 'TEST-EXTRA' => [ ['Digest::MockA', 10] ] );
    my $obj = Digest->new('TEST-EXTRA', 'user_arg');
    is_deeply( $obj->{args}, [10, 'user_arg'],
        'User args are appended after MMAP args' );
}

# --- Test 10: Already-loaded module skips require ---
{
    # Digest::MockA has $VERSION set and is in memory.
    # This should NOT attempt to require it from disk.
    local %Digest::MMAP = ( 'LOADED' => 'Digest::MockA' );
    my $obj = Digest->new('LOADED');
    isa_ok( $obj, 'Digest::MockA', 'Already-loaded module is used without require' );
}

# --- Test 11: Uses Digest::Dummy from t/lib (real file require) ---
{
    my $obj = Digest->new('Dummy');
    isa_ok( $obj, 'Digest::Dummy', 'Can load module from disk via require' );
    is( $obj->digest, 'ooo', 'Loaded module works correctly' );
}

# --- Test 12: Digest->new with Dummy args passthrough ---
{
    my $obj = Digest->new('Dummy', 'custom');
    is( $obj->digest, 'custom', 'User args passed to loaded module constructor' );
}
