use Test::More qw/no_plan/;

use_ok ('RT::Action::LinearEscalate');
can_ok(MyEscalator, 'new');
can_ok(MyEscalator, 'Prepare');


my $foo = MyEscalator->new();
isa_ok($foo, 'RT::Action::LinearEscalate');


#make sure nondue tickets don't get changed
eval "sub MyEscalator::_DueAsEpoch{ return 0 }";

is($foo->Prepare,0);


# Make sure overdue tickets don't get changed
eval "sub MyEscalator::_DueAsEpoch {return (time - 1);}" ;
eval "sub MyEscalator::_CreatedAsEpoch {return (time - 86400 * 5);}" ;
is ($foo->Prepare,1);
is ($foo->{'prio'}, &MyEscalator::_FinalPriority, "overdue tickets are at final prio");

eval "sub MyEscalator::_Priority { 60 } ";

is ($foo->Prepare,0, "But tickets that are over their final priority don't get touched");

$foo->{'prio'} = undef;

eval "sub MyEscalator::_FinalPriority { 63 } ";
eval "sub MyEscalator::_InitialPriority { 0 } ";
eval "sub MyEscalator::_Priority { 0 } ";
eval "sub MyEscalator::_CreatedAsEpoch { time() } ";
eval "sub MyEscalator::_DueAsEpoch { time() + (86400*21) }";



ok(!$foo->Prepare(), "on the first day, don't escalate");

eval "sub MyEscalator::_Now { time() + (86400  * 7)} ";
ok($foo->Prepare());
is ($foo->{'prio'}, 21, "One week in  the second day, priority is 21");


eval "sub MyEscalator::_Now { time() + (86400 * 14) } ";
$foo->Prepare();
is ($foo->{'prio'}, 42, "Two weeks in, we're at 42");
eval "sub MyEscalator::_Now { time() + (86400 * 21) } ";
$foo->Prepare();
is ($foo->{'prio'}, 63, "At the due date, priority is 63");



package MyEscalator;

use base qw/RT::Action::LinearEscalate/;


sub _Priority { 0 }
sub _FinalPriority { 50 }
sub _InitialPriority { 0 }
sub _CreatedAsEpoch { time() - (86400 * 2) }
sub _DueAsEpoch { time() + (86400*8) }

sub _Init {}


1;
