# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2006 Best Practical Solutions, LLC
#                                          <jesse@bestpractical.com>
#
# (Except where explicitly superseded by other copyright notices)
#
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# END BPS TAGGED BLOCK }}}

=head1 NAME

RT::Action::LinearEscalate - will move a ticket's priority toward its
final priority.

=head1 DESCRIPTION

LinearEscalate is a ScripAction that will move a ticket's priority
from its initial priority to its final priority linearly as
the ticket approaches its due date.

It's intended to be called by an RT escalation tool. One such tool is called
rt-crontool and is located in $RTHOME/bin (see C<rt-crontool -h> for more details).

=head1 INSTALLATION

To install this package run:

    perl Makefile.PL
    make install

=head1 CONFIGURATION

Once the ScripAction is installed, the following script in "cron" 
will get tickets to where they need to be:

    rt-crontool --search RT::Search::FromSQL --search-arg \
    "(Status='new' OR Status='open' OR Status = 'stalled')" \
    --action RT::Action::LinearEscalate

LinearEscalate's behavior can be controlled by two options:

=over 4

=item RecordTransaction - defaults to false and if option is true then
causes the tool to create a transaction on the ticket when it is escalated.

=item UpdateLastUpdated - which defaults to true and updates the LastUpdated
field when the ticket is escalated, otherwise don't touch anything.

=back

You cannot set "UpdateLastUpdated" to false unless "RecordTransaction"
is also false. Well, you can, but we'll just ignore you.

You can set this options using either in F<RT_SiteConfig.pm>, as action
argument in call to the rt-crontool or in DB if you want to use the action
in scrips.

You should prefix options with C<LinearEscalate_> in the config:

    Set( $LinearEscalate_RecordTransaction, 1 );
    Set( $LinearEscalate_UpdateLastUpdated, 1 );

From a shell you can use the following command:

    rt-crontool --search RT::Search::FromSQL --search-arg \
    "(Status='new' OR Status='open' OR Status = 'stalled')" \
    --action RT::Action::LinearEscalate \
    --action-arg "RecordTransaction: 1"

This ScripAction uses RT's internal RT::Ticket::_Set call to set ticket
priority without running scrips or recording a transaction on each
update.

=cut

package RT::Action::LinearEscalate;

use strict;
use warnings;
use base qw(RT::Action::Generic);

our $VERSION = '0.05';

my $RecordTransaction = ( defined $RT::LinearEscalate_RecordTransaction 
                            ? $RT::LinearEscalate_RecordTransaction : 0 
                        );
my $UpdateLastUpdated = ( defined $RT::LinearEscalate_UpdateLastUpdated 
                            ? $RT::LinearEscalate_UpdateLastUpdated : 1
                        );

#Do what we need to do and send it out.

#What does this type of Action does

sub Describe {
    my $self = shift;
    my $class = ref($self) || $self;
    return "$class will move a ticket's priority toward its final priority.";
}

sub Prepare {
    my $self = shift;

    my $ticket = $self->TicketObj;

    my $due = $ticket->DueObj->Unix;
    unless ( $due > 0 ) {
        $RT::Logger->debug('Due is not set. Not escalating.');
        return 1;
    }

    my $priority_range = $ticket->FinalPriority - $ticket->InitialPriority;
    unless ( $priority_range ) {
        $RT::Logger->debug('Final and Initial priorities are equal. Not escalating.');
        return 1;
    }

    if ( $ticket->Priority >= $ticket->FinalPriority && $priority_range > 0 ) {
        $RT::Logger->debug('Current priority is greater than final. Not escalating.');
        return 1;
    }
    elsif ( $ticket->Priority <= $ticket->FinalPriority && $priority_range < 0 ) {
        $RT::Logger->debug('Current priority is lower than final. Not escalating.');
        return 1;
    }

    # TODO: compute the number of business days until the ticket is due

    # now we know we have a due date. for every day that passes,
    # increment priority according to the formula

    my $starts         = $ticket->StartsObj->Unix;
    $starts            = $ticket->CreatedObj->Unix unless $starts > 0;
    my $now            = time;

    # do nothing if we didn't reach starts or created date
    if ( $starts > $now ) {
        $RT::Logger->debug('Starts(Created) is in future. Not escalating.');
        return 1;
    }

    $due = $starts + 1 if $due <= $starts; # +1 to avoid div by zero

    my $percent_complete = ($now-$starts)/($due - $starts);

    my $new_priority = int($percent_complete * $priority_range) + $ticket->InitialPriority;
	$new_priority = $ticket->FinalPriority if $new_priority > $ticket->FinalPriority;
    $self->{'new_priority'} = $new_priority;

    return 1;
}

sub Commit {
    my $self = shift;

    my $new_value = $self->{'new_priority'};
    return 1 unless defined $new_value;

    my $ticket = $self->TicketObj;
    # if the priority hasn't changed do nothing
    return 1 if $ticket->Priority == $new_value;

    # override defaults from argument
    my ($record, $update) = ($RecordTransaction, $UpdateLastUpdated);
    {
        my $arg = $self->Argument || '';
        if ( $arg =~ /RecordTransaction:\s*(\d+)/i ) {
            $record = $1;
            $RT::Logger->debug("Overrode RecordTransaction: $record");
        } 
        if ( $arg =~ /UpdateLastUpdated:\s*(\d+)/i ) {
            $update = $1;
            $RT::Logger->debug("Overrode UpdateLastUpdated: $update");
        }
        $update = 1 if $record;
    }

    $RT::Logger->debug(
        'Linearly escalating priority of ticket #'. $ticket->Id
        .' from '. $ticket->Priority .' to '. $new_value
        .' and'. ($record? '': ' do not') .' record a transaction'
        .' and'. ($update? '': ' do not') .' touch last updated field'
    );

    my ( $val, $msg );
    unless ( $record ) {
        unless ( $update ) {
            ( $val, $msg ) = $ticket->__Set(
                Field => 'Priority',
                Value => $new_value,
            );
        }
        else {
            ( $val, $msg ) = $ticket->_Set(
                Field => 'Priority',
                Value => $new_value,
                RecordTransaction => 0,
            );
        }
    }
    else {
        ( $val, $msg ) = $ticket->SetPriority( $new_value );
    }

    unless ($val) {
        $RT::Logger->error( "Couldn't set new priority value: $msg" );
        return (0, $msg);
    }
    return 1;
}

eval "require RT::Action::LinearEscalate_Vendor";
die $@ if ( $@ && $@ !~ qr{^Can't locate RT/Action/LinearEscalate_Vendor.pm} );
eval "require RT::Action::LinearEscalate_Local";
die $@ if ( $@ && $@ !~ qr{^Can't locate RT/Action/LinearEscalate_Local.pm} );

1;
