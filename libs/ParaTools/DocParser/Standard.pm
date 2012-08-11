######################################################################
#
# ParaTools::DocParser::Standard;
#
######################################################################
#
#  This file is part of ParaCite Tools
#
#  Copyright (c) 2002 University of Southampton, UK. SO17 1BJ.
#
#  ParaTools is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  ParaTools is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with ParaTools; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
######################################################################

package ParaTools::DocParser::Standard;
require Exporter;
@ISA = ("Exporter", "ParaTools::DocParser");

use 5.006;
use strict;
use warnings;

our @EXPORT_OK = ( 'get_references', 'new' );

=pod

=head1 NAME

B<ParaTools::DocParser::Standard> - document parsing functionality

=head1 SYNOPSIS

  use ParaTools::DocParser::Standard;
  use ParaTools::Utils;
  # First read a file into an array of lines.
  my @lines = ParaTools::Utils::get_line("http://www.foo.com/myfile.pdf");
  my $doc_parser = new ParaTools::DocParser::Standard();
  my @references = $doc_parser->get_references(@lines);
  # Print a list of the extracted references.
  foreach(@references) { print "-> $_\n"; } 

=head1 DESCRIPTION

ParaTools::DocParser::Standard provides a fairly simple implementation of
a system to extract references from documents. 

Various styles of reference are supported, including numeric and indented,
and documents with two columns are converted into single-column documents
prior to parsing. This is a very experimental module, and still contains
a few hard-coded constants that can probably be improved upon.

=head1 METHODS

=over 4

=item $parser = ParaTools::DocParser::Standard-E<gt>new()

The new() method creates a new parser instance.

=cut

sub new
{
        my($class) = @_;
        my $self = {};
        return bless($self, $class);
}

=pod

=item @references = $parser-E<gt>get_references(@lines)

The get_references() method takes a list of lines as input (see the get_lines()
function in ParaTools::Utils for a way to obtain this), and returns a list
of references in plain text suitable for passing to a CiteParser module. 

=cut

sub get_references
{
	my($self, @lines) = @_;

	my($pivot, $avelen) = $self->_decolumnise(@lines); 
	
	my $in_refs = 0;
	my @ref_table = ();
	my $curr_ref = "";
	my @newlines = ();
	my $outcount = 0;
	my @chopped_lines = @lines;
	# First isolate the reference array. This ensures that we handle columns correctly.
	foreach(@lines)
	{
		$outcount++;
		chomp;
		if (/\s*references\s*/i || /REFERENCES/ || /Bibliography/i)
                {
                        last;
                }
		elsif (/\f/)
		{
			# No sign of any references yet, so pop off up to here
			for(my $i=0; $i<$outcount; $i++) { shift @chopped_lines; }
			$outcount = 0;
		}
	}
	my @arr1 = ();
	my @arr2 = ();
	my @arrout = ();
	my $indnt = "";
	if ($pivot)
	{
		foreach(@chopped_lines)
		{
			chomp;
			s/^(\s{3,8})(\S)/$2/;
			$indnt = $1;
			if (/\f/)
			{
				push @arrout, @arr1;
				push @arrout, @arr2;
				@arr1 = ();
				@arr2 = ();
			}
			else
			{
				
				if(/^(.+?)\s\s\s+(.*?)$/)
				{
					push @arr1, $indnt.$1;
					push @arr2, $2;
				}
				else
				{
					push @arr1, $indnt.$_;
				}
			}
		}
		push @arrout, @arr1;
		push @arrout, @arr2;
		@chopped_lines = @arrout;
	}
	my $prevnew = 0;
	foreach(@chopped_lines)
	{
		chomp;
		if (/^\s*references\s*$/i || /REFERENCES/ || /Bibliography/i || /References and Notes/)
                {
                        $in_refs = 1;
                        next;
                }
		if (/^\s*\bappendix\b/i || /_{6}/ || /^\s*\btable\b/i || /wish to thank/i || /\bfigure\s+\d/)
		{
			$in_refs = 0;
		}

		if (/^\s*$/)
		{
			if ($prevnew) { next; }
			$prevnew = 1;
		}
		else
		{
			$prevnew = 0;
		}

		if (/^\s*\d+\s*$/) { next; } # Page number

		if ($in_refs)
		{
			push @newlines, $_;
		}
	}
	# Work out what sort of separation is used
	my $type = 0;
	my $TYPE_NEWLINE = 0;
	my $TYPE_INDENT = 1;
	my $TYPE_NUMBER = 2;
	my $TYPE_NUMBERSQ = 3;
	my $numnew = 0;
	my $numnum = 0;
	my $numsq = 0;
	my $indmin = 255;
	my $indmax = 0;
	foreach(@newlines)
	{
		if (/^\s*$/)
		{
			$numnew++;
		}
		if (/^(\s+)\b/)
		{
			if (length $1 < $indmin) { $indmin = length $1; }
			if (length $1 > $indmax) { $indmax = length $1; }
		}
		if (/^\s*\d+\.?\s+[[:alnum:]]/)
		{
			$numnum++;
		}
		if (/^\s*\[\d+\]\s+[[:alnum:]]/)
		{
			$numsq++;	
		}
	}
	
	if ($numnew < ($#newlines-5) && ($indmax > $indmin) && $indmax != 0 && $indmin != 255 && $indmax < 24) { $type = $TYPE_INDENT; }
	if ($numnum > 1) { $type = $TYPE_NUMBER; }
	if ($numsq > 1) { $type = $TYPE_NUMBERSQ; }
	if ($type == $TYPE_NEWLINE)
	{
		foreach(@newlines)
		{
			if (/^\s*$/)
			{
				if ($curr_ref) { push @ref_table, $curr_ref; }
				$curr_ref = "";
				next;
			}
			# Trim off any whitespace surrounding chunk
			s/^\s*(.+)\s*$/$1/;
			s/^(.+)[\\-]+$/$1/;
			if ($curr_ref =~ /http:\/\/\S+$/) { $curr_ref = $curr_ref.$_;} else
			{
				$curr_ref = $curr_ref." ".$_;  
			}
		}
		if ($curr_ref) { push @ref_table, $curr_ref; }
	}		
	elsif ($type == $TYPE_INDENT)
	{
		foreach(@newlines)
		{
			/^(\s*)\b/;
			if (length $1 == $indmin)
			{
				if ($curr_ref) { push @ref_table, $curr_ref; }
				$curr_ref = $_;
				next;
			}
			else
			{
				# Trim off any whitespace surrounding chunk
				s/^\s*(.+)\s*$/$1/;
				if ($curr_ref =~ /http:\/\/\S+$/) { $curr_ref = $curr_ref.$_;} else
				{
					$curr_ref = $curr_ref." ".$_;  
				}

			}
		}
		if ($curr_ref) { push @ref_table, $curr_ref; }
	}
	elsif ($type == $TYPE_NUMBER)
	{
		foreach(@newlines)
		{
			s/^\s*(.+)\s*$/$1/;
			if (/^\s*\d+\.?\s+[[:alnum:]].+$/)
			{
				if ($curr_ref) { push @ref_table, $curr_ref; }
				$curr_ref = $_;
				next;
			}
			else
			{
				if ($curr_ref =~ /http:\/\/\S+$/) { $curr_ref = $curr_ref.$_;} else
				{
					$curr_ref = $curr_ref." ".$_;  
				}

			}
		}
		if ($curr_ref) { push @ref_table, $curr_ref; }
	}
	elsif ($type == $TYPE_NUMBERSQ)
	{
		foreach(@newlines)
		{
			s/^\s*(.+)\s*$/$1/;
			if (/^\s*\[\d+\]\s.+$/)
			{
				if ($curr_ref) { push @ref_table, $curr_ref; }
				$curr_ref = $_;
				next;
			}
			else
			{
				if ($curr_ref =~ /http:\/\/\S+$/) { $curr_ref = $curr_ref.$_;} else
				{
					$curr_ref = $curr_ref." ".$_;  
				}

			}
		}
		if ($curr_ref) { push @ref_table, $curr_ref; }
	}

	my @refs_out = ();
	# A little cleaning up before returning	
	foreach (@ref_table)
	{
		s/([[:alpha:]])\-\s+/$1/g;
		s/^\[.+\](.+)$/$1/;
		s/\s\s+/ /g;
		s/^\s*(.+)\s*$/$1/;
		next if length $_ > 200;
		push @refs_out, $_;
	}
	return @refs_out;
}

# Private method to determine if/where columns are present.

sub _decolumnise 
{
	my($self, @lines) = @_;
	my @bitsout = ();
	my %lens = ();
	foreach(@lines)
	{
		# Replaces tabs with 8 spaces
		s/\t/        /g;
		# Split into characters
		my @bits = unpack "c*", $_;
		$lens{scalar @bits}++;	
		my @newbits = map { $_ = ($_==32?1:0) } @bits;
		for(my $i=0; $i<$#newbits; $i++) { $bitsout[$i]+=$bits[$i]; } 
	}
	# Calculate the average length based on the modal.
	my %lens2 = reverse %lens;
	my @key_list = reverse sort keys %lens2;
	my $avelen = $lens2{$key_list[0]};
	my $maxpoint = 0;
	my $max = 0;
	# Determine which point has the most spaces
	for(my $i=0; $i<$#bitsout; $i++) { if ($bitsout[$i] > $max) { $max = $bitsout[$i]; $maxpoint = $i; } }
	my $center = int($avelen/2);
	my $output = 0;
	# Only accept if the max point lies around the average center.
	if ($center-6 <= $maxpoint && $center+6>= $maxpoint) { $output = $maxpoint; } else  {$output = 0;}
	return ($output, $avelen); 
}

__END__

=back

=pod

=head1 AUTHOR

Mike Jewell <moj@ecs.soton.ac.uk>

=cut
