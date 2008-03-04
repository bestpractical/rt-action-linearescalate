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

  RT::Action::LinearEscalate

=head1 DESCRIPTION

LinearEscalate is a ScripAction which is NOT intended to be called
per transaction. It's intended to be called by an RT escalation tool.
One such tool is called rt-crontool and is located in $RTHOME/bin (see
C<rt-crontool -h> for more details)

This ScripAction will move a ticket's priority from its initial priority to
its final priority linearly as the ticket approaches its due date. 

This ScripAction uses RT's internal Ticket::_Set call to set ticket
priority without running scrips or recording a transaction on each
update. 

To install this package:

 # perl Makefile.PL
 # make install

Once the ScripAction is installed, the following script in "cron" 
will get tickets to where they need to be:

 rt-crontool --search RT::Search::FromSQL --search-arg \
    "(Status='new' OR Status='open' OR Status = 'stalled')" \
    --action RT::Action::LinearEscalate

LinearEscalate's behavior can be controlled by two configuration options
set in RT_SiteConfig.pm -- LinearEscalate_RecordTransaction, which 
defaults to false and causes the tool to create a transaction on the 
ticket when it is escalated, and LinearEscalate_UpdateLastUpdated, which 
defaults to true and updates the LastUpdated field when the ticket is 
escalated.  You cannot set LinearEscalate_UpdateLastUpdated to false 
unless LinearEscalate_RecordTransaction is also false.  (Well, you can,
but we'll just ignore you.)


=cut

package RT::Action::LinearEscalate;
require RT::Action::Generic;

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
    return (
        ref $self
          . " will move a ticket's priority toward its final priority." );
}

sub Prepare {
    my $self = shift;

    my $ticket = $self->TicketObj;
    if ( $ticket->Priority >= $ticket->FinalPriority ) {
        # no update necessary.
        return 0;
    }

    #compute the number of business days until the ticket is due

    # If we don't have a due date, get out
    my $due = $ticket->DueObj->Unix; 
    return 0 unless $due > 0;

    # now we know we have a due date. for every day that passes,
    # increment priority according to the formula

    my $standard_range = $ticket->FinalPriority - $ticket->InitialPriority;
    my $created        = $ticket->CreatedObj->Unix;
    my $now            = time;

    $due = $created + 1 if $due <= $created; # +1 to avoid div by zero

    my $percent_complete = ($now-$created)/($due - $created);

    my $new_priority = int($percent_complete * $standard_range) + $ticket->InitialPriority;
	$new_priority = $ticket->FinalPriority if $new_priority > $ticket->FinalPriority;
    # if the priority hasn't changed do nothing
    if ( $ticket->Priority == $new_priority ) {
        return 0;
    }

    $self->{'new_priority'} = $new_priority;

    return 1;
}

# }}}

sub Commit {
    my $self = shift;

    my $ticket = $ticket->TicketObj;

    my ( $val, $msg );

    #testing purposes only, it's a dirty ugly hack
    if ($self->Argument =~ /RecordTransaction:(\d); UpdateLastUpdated:(\d)/) {
        $RecordTransaction = (defined $1 ? $1 : $RecordTransaction);
        $UpdateLastUpdated = (defined $2 ? $2 : $UpdateLastUpdated);
        $RT::Logger->warning("Overrode RecordTransaction: $RecordTransaction") 
            if defined $1;
        $RT::Logger->warning("Overrode UpdateLastUpdated: $UpdateLastUpdated") 
            if defined $2;
    }

    if ( $ticket->Priority < $self->{'prio'} ) {
        unless ($RecordTransaction) {

        $RT::Logger->warning( "Updating priority of ticket",
                              $ticket->Id,
                              "from", $ticket->Priority,
                              "to", $self->{'prio'} );


            unless ($UpdateLastUpdated) {
                ( $val, $msg ) = $ticket->__Set( Field => 'Priority',
                                                          Value => $self->{'prio'},
                                                         );
            }
            else {
                ( $val, $msg ) = $ticket->_Set( Field => 'Priority',
                                                         Value => $self->{'prio'},
                                                         RecordTransaction => 0,
                                                        );
            }
        }
        else {
            ( $val, $msg ) = $ticket->SetPriority( $self->{'prio'} );
        }
        unless ($val) {
            $RT::Logger->debug( $self . " $msg\n" );
        }
    }
}

eval "require RT::Action::LinearEscalate_Vendor";
die $@ if ( $@ && $@ !~ qr{^Can't locate RT/Action/LinearEscalate_Vendor.pm} );
eval "require RT::Action::LinearEscalate_Local";
die $@ if ( $@ && $@ !~ qr{^Can't locate RT/Action/LinearEscalate_Local.pm} );

1;
