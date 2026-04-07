#!/usr/bin/env perl

# Security tests: eval-based require patterns are exploitable

use strict;
use warnings;

use Test::More tests => 2;

use Digest;

# Test 1: Digest->new() had an exploitable eval
$LOL::PWNED = 0;
eval { Digest->new(q[MD;5;$LOL::PWNED = 42]) };
is $LOL::PWNED, 0, 'Digest->new does not eval-inject via module name';

# Test 2: digest-bench must not allow code injection via module name
# With eval "require $mod", an attacker can append arbitrary Perl after a
# valid module name. The payload executes inside the eval and can create
# files, open sockets, etc. A safe bare require prevents this entirely.
{
    use File::Temp qw(tmpnam);
    my $canary = tmpnam();
    # Payload: require a real module, then create a canary file as proof of execution
    my $payload = qq{Digest::MD5; open my \\\$fh, '>', '$canary'};
    `$^X digest-bench "$payload" 2>&1`;
    ok(! -e $canary, 'digest-bench does not execute injected code in module name');
    unlink $canary if -e $canary;    # cleanup if test fails
}
