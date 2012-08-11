package Parser::Citation;

# Copyright 2001, University of Southampton, UK 
# See LICENSE.TXT for license information. 

#/* $Author: zj $ */
#/* $Id: Citation.pm,v 1.30 2001/06/22 15:55:35 zj Exp zj $ */
#/* $Date: 2001/06/22 15:55:35 $ */  

#/* Citation.pm: extract metadata from a citation string (in plain text).
#/* Author: Zhuoan Jiao, IAM Research Group, University of Southampton
#/* Email: zj@ecs.soton.ac.uk
#/* Documentation: is at the end of this module, in the pod format.

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK);
use Parser::Utility;
use XML::Element;

require Exporter;

@ISA = qw(Exporter);
@EXPORT_OK = qw(&srcText &list_authors &first_author &aulast
             &aufirst &auinit &jtitle &atitle &volume
             &issue &supplement &startpage &year &featureID
	     &display_metadata display_metadata_xml);

sub new {
        my $class = shift;
        my $cite = {};
        bless $cite, $class;
        $cite->initialize(@_);
        return $cite;
}  

sub initialize {
        my $cite = shift;
	my $text = shift || return;

	$cite->{'text'} = $text;
	$cite->{'rest_text'} = $cite->{'text'};
 
        $cite->{'aufull'} = '';
        $cite->{'aulast'} = '';
        $cite->{'aufirst'}= '';
        $cite->{'auinit'} = '';
	$cite->{'authors'}= '';
        $cite->{'atitle'} = '';
        $cite->{'jtitle'} = '';
        $cite->{'volume'} = '';
        $cite->{'issue'}  = '';
	$cite->{'supl'}	= '';
        $cite->{'spage'}  = '';
        $cite->{'year'}   = '';
	$cite->{'targetURL'}  = '';
	$cite->{'eprintID'} = '';

	$cite->{'featureID'} = '';	
	$cite->{'jnl_spos'}  = 0;
	$cite->{'jnl_epos'}  = 0;
	$cite->{'num_of_fig'}= 0;

	$cite->find_metadata();
	$cite->find_featureID();
}

#
# Actions 
#
sub pre_process {
	my $cite = shift;
	my $Text = $cite->{'text'};

	$Text = normalisation($Text);
	$Text = normalise_date($Text);
	$Text = normalise_html($Text);
	# remove front label to get accurate $nFig 
	# (Note: do not perform this for arXiv ref. like: "46(4), 90 (1993)")
	# [Smith, 1998], [1], (1), (1a) ... 
	$Text =~ s/^\s*[\[(]\s*  # bracket
		   ([^\])]+?)\s* # content
	           [\])]\s*//x;  # bracket

	# "1. Gary Smith, ...." 
	$Text =~ s/^\d+\s*\.\s+//;
	# "1 Gary Smith, ...."
	$Text =~ s/^\s*\d+ ([A-Z])/$1/;
	# "2) Brand, P. ..."    
	$Text =~ s/^[\[\(]?\s*\w+\s*[\])]\s*//; 
 
	$cite->{'rest_text'} = $Text;

	my $nFig = num_of_figures($Text);
	$cite->{'num_of_fig'} = $nFig;	
}

sub find_metadata {
	my $cite = shift;

	return 0 if (!defined($cite->{'text'}));

	$cite->pre_process();

	# find URL
        $cite->find_url();  

	my $nFig = $cite->{'num_of_fig'};

	# find the authors
	if ($cite->find_authors()) {
	      $cite->find_first_author()
	      };

	# find article titile
	$cite->find_atitle(); 

	# only process references to 'journal' articles.
        return 0 if ($nFig == 0) ; # no number, ignore.
        return 0 if ($nFig >= 8); # too many numbers, maybe an error, ignore.
        # return 0 if ($cite->{'rest_text'} =~ /\W(proc.|proceedings) of /i);    

	# extract 'supplement' first before find_vol_no_pg_year()
	$cite->find_supplement();

        if ($cite->find_vol_no_pg_year() or
            $cite->find_vol_pg_year()) {
 
                $cite->find_jnl_name();
                return 1
                };

	if ($cite->guess_vol_no_pg()) {
		$cite->find_jnl_name();
		return 1;
		};

        if ($cite->find_vol_no() or
            $cite->find_vol_supl()) {
 
                $cite->find_jnl_name();
                $cite->find_page();
                $cite->find_year();
 
                return 1;
                };

        if ($cite->guess_vol_pg()) {
		$cite->find_year(); 
                $cite->find_jnl_name();
 
                return 1;
                };
 
        if ($cite->guess_vol_year()) {

		$cite->find_page(); 
                $cite->find_jnl_name();
 
                return 1;
                };

	my $Count = 0; 
        $Count++ if ($cite->find_vol());
	$Count++ if ($cite->find_issue());
	$Count++ if ($cite->find_supplement());
        $Count++ if ($cite->find_jnl_name());
        $Count++ if ($cite->find_page());
        $Count++ if ($cite->find_year());
 
        return 1 if ($Count >=2 );
 
        # too few metadata 
        return 0
	}

sub find_atitle {
	my $cite = shift;
	my $Text = $cite->{'rest_text'};
  
	# title is quoted.
	# return 0 if ($Text !~  /(['"])/); # 
	# my $Qt = $1;
	# ignore ' case, because author nams may contain ', e.g.
	#    A. I. L'vov, V. A. Petrun'kin, and M. Schumacher, 
        #    Phys. Rev. C 55, 359 (1997)
	return 0 if ($Text !~  /"/);

	if ($Text =~ /"(.+?)"\s*\.?/ and 
    	    word_count($1) >= 2) {
		my $Guess_title = $1;
		return 0 if ($Guess_title =~ /^http:/i);
	       
		$cite->{'atitle'} = $Guess_title;
		# use ';' !  
		# $Text =~ s/$Qt(.+?)$Qt\s*\.?/;/o;
		# $Text =~ s/"[^"]+"\s*\.?/;/;
		$Text =~ s/"[^"]+"/" "/;
		# $Text =~ s/[,;.]\s*[,;.]/,/g; # doesn't work
		while ($Text =~ /[,;.]\s*[,;.]/g) { 
			$Text =~ s/[,;.]\s*[,;.]/,/
			};	
		$Text =~ s/^[;" ]+//;
		$cite->{'rest_text'} = $Text;
		return 1
		};

	return 0
}

# for the OpCit Project .
sub find_featureID {
	my $cite = shift;

	my $featureID = '';
	$featureID .= "v$cite->{'volume'}" if ($cite->{'volume'});
	$featureID .= ":n$cite->{'issue'}" if ($cite->{'issue'});
	$featureID .= ":s$cite->{'supl'}"  if ($cite->{'supl'});
	$featureID .= ":p$cite->{'spage'}" if ($cite->{'spage'});
	$featureID .= ":y$cite->{'year'}"  if ($cite->{'year'});

	# tidy up
	# $featureID =~ s/:[nsp]\s*:/:/g; # doesn't work.
	while ($featureID =~ /:[nsp]\s*:/g) {
               $featureID =~ s/:[nsp]\s*:/:/
               };
	$featureID =~ s/^://;
	$featureID =~ s/\s+//g;

	my @Features = split(':', $featureID);

	# ignore those having too few metadata
	if (scalar(@Features) >= 2) {
		# standardize
		$featureID = lc($featureID);
		$cite->{'featureID'} = $featureID;
		};
	}


sub find_authors {
        my $cite = shift;
        my $Text = $cite->{'rest_text'};
 
        my $aText = locate_authors($Text);
        return 0 if ($aText eq '' or $aText =~ /^\W+$/);
 
        my @Chunks  = ();
        @Chunks = split(/\s*[,;:]\s*/, $aText);
 
        # ignore text longer than 4 words (don't count initials)
        return 0 if (word_count($Chunks[0])>4 and no_initials($Chunks[0])); 
		
	my($author, $Authors) = ('','');
        while (@Chunks) { 
            if (scalar(@Chunks)==1) {
                    last if !full_name($Chunks[0]);
                    $author = normalise_name($Chunks[0]); 
		    $Authors = "$Authors:$author";
                    last   
		    };
 

            # (1) forename and surname are not separated by [,;].
	    if (full_name($Chunks[0])){
                if ($Chunks[1] =~ /^\s*Jr\.?\s*$/i) {
                        $author = "$Chunks[0], $Chunks[1]";
                        $author = normalise_name($author);
                        $Authors = "$Authors:$author";
                        splice(@Chunks, 0, 2); # remove the first two
                        next
                        }
                elsif (!only_initials($Chunks[1])) {
                        $author = normalise_name($Chunks[0]);
                        $Authors = "$Authors:$author";
                        shift(@Chunks);
                        next
                        }
                }
	    elsif (full_name($Chunks[1])) {
			# $Chunks[0] is not a name, skip. 
			shift @Chunks;
			next 
		};

            # (2) forename and surname are separated by [,;].
            # Ignore text containing too many words.
            my $aFull = "$Chunks[0] $Chunks[1]";
	    my @abbr = ();
            last if (word_count($aFull) > 4);
	    last if ($aFull =~ /[\d\/]+/);
	    
	    # journal title maybe mixed up with the name 
	    last if (@abbr = ($aFull =~ /\w\w\./g) and (@abbr >= 2)); 

            # surname first.
	    # "Oemler, A., Jr.  and  Lynds, C. R. 1975, ApJ, 199, 558"
	    if (scalar(@Chunks) > 2) {
                if (is_surname($Chunks[0]) and
                    has_initials($Chunks[1]) and
		    $Chunks[2] =~ /^\s*Jr\.?\s*$/i) {
                        $author = "$Chunks[1] $Chunks[0], Jr";
                        $author = normalise_name($author);
                        $Authors = "$Authors:$author";
                        splice(@Chunks, 0, 3); # remove the first three 
                        next
                        };
		};

	    # surname first
	    # "Reisenegger, A.  and  Miralda-Escude, J. 1995, ApJ, 449, 476 
            if (is_surname($Chunks[0]) and
                has_initials($Chunks[1])) {
		    if ($Chunks[1] =~ /(.+?\.?)\s*Jr\.?\s*$/i){
                        $author = "$1 $Chunks[0], Jr";
		        }
		    else 
		       {
			$author = "$Chunks[1] $Chunks[0]"; 
			};
                    $author = normalise_name($author);
                    $Authors = "$Authors:$author";
                    splice(@Chunks, 0, 2); # remove the first two
                    next
                    };
 
            # forename first
            if (only_initials($Chunks[0]) and
                is_surname($Chunks[1])) { 
                    if ($Chunks[0] =~ /(.+?[. ])\s*Jr\.?\s*$/i){
                        $author = "$1 $Chunks[1], Jr";
                        }
                    else
                       {
                        $author = $aFull 
                        };                                      
                    $author = normalise_name($author);
                    $Authors = "$Authors:$author";
                    splice(@Chunks, 0, 2); # remove the first two
                    next
                    };
 
            #  'Liu, Gong', hard to tell which is the surname;
            if (no_initials($Chunks[0]) and
                no_initials($Chunks[1])) {
                    if (word_count($aFull) <= 4 ) {
                            $author = normalise_name($aFull);
                            $Authors = "$Authors:$author";
                            splice(@Chunks, 0, 2); # remove the first two
                            next
                            }
            };
 
            # cannot determin the author name
            last 
 
            }; # end of while
	
	return 0 if ($Authors eq '');
	$Authors =~ s/^://;	
	$cite->{'authors'} = $Authors;
        } 

sub find_first_author {
	my $cite = shift;
	
	return 0 if ($cite->{'authors'} eq '');

	my @Authors = split(':', $cite->{'authors'});
	$cite->{'aufull'} = shift @Authors;
	}


# locate_authors 
sub locate_authors {
	my $Text = shift;

	$Text =~ s/^\s*For .*?review(s)?\W+//i;
	$Text =~ s/^\s*(see )?also //i;
	$Text =~ s/^\s*see[, ]\s*for example\W+//i;
	$Text =~ s/^\s*see e\.g\.\W+//i;
	my $aText = $Text;

        # author name(s) is assumed to be in front of a consecutive
        # 4 words, e.g. J. A. Harvey. String Duality and Non-supersymmetric
        # Strings.
	# if ($Text =~ /\b([\w\-'`"]+\s+){3,}[\w\-'"]+\b/){
	if ($Text =~ /\.\s+([\w\-'`"]+\s+){3,}[\w\-'"]{2,}\b/){ 
                $aText = $`;
                };

	if ($Text =~ /[,;]\s*([\w\-'`"]{2,}\s+){3,}[\w\-'"]{2,}\b/) {
		$aText = $`;	
		};
	# the above has truncated too much.
	# "S. Popescu and Sudbery G. A. Multi-particle entanglement ..."
	if (only_initials($aText)) {
		$aText = $Text
		};

	if ($aText =~ /[,:; ]\s*[a-z][\w\-'"]*\s+([a-z0-9\-'"]+\s+)*?[a-z0-9\-'"]{4,}(\b|$)/) { # "[6] M.Gotay, Constraints, reduction and quantization, 
	  #      J. Math. Phys. (1986) 2051.
                $aText = $`;
                };
 
	# Or before the following sybmols.
        # if ($aText =~ /["\[\(]/) {
	if ($aText =~ /[:"\[\(]/) {
                $aText = $`
                };


	# before '/', e.g. "Halzen F. astro-ph/0001001"
	if ($aText =~ /\S+\//) {
		$aText = $` 
		};

	# before any number
	if ($aText =~ /\d+/i) {
		$aText = $`
		};

	# "14. A. J. Leggett, in Percolation, Localization and ..."
	if ($aText =~ /[,;: ]\s*in /i) {
		$aText = $`
		};

	# last author name after 'and'.
	if ($aText =~ /[,; ]\s*and ([^,;:]+)[,:;]([^,;:]+)/i) {
	    my $Aft1 = $1;
	    my $Aft2 = $2;
	    if (full_name($Aft1)) {
		$aText = $` .", $Aft1";
		} else {
		$aText = $` .", $Aft1, $Aft2"
		}
	    };

	# 
        # tidy up 
	#
	# remove non-alphabets 
	$aText =~ s/^[^a-z]+//i;
	$aText =~ s/^by //i;
	$aText =~ s/[,; ]+and /,/i;
	$aText =~ s/[,; ]+et\.?\s+al\.?([,; ]+|$)/,et al,/i;
       #$aText =~ s/[,;:.]+\s*$//;
	$aText =~ s/[,;:]+\s*$//;

        return $aText
        };  

# This subroutine needs re-written; not in use now. 
sub locate_book {
        my $cite = shift;
        my $Text = $cite->{'rest_text'};
 
        if ($Text =~ /\W+in\s+(.+?)\W+(ed|eds|edited)\.?(\W|$)/) {
                $$cite{book} = $1;
                return 1
                };
        return 0
 
        }  

sub find_vol_no {
        my $cite = shift;
        my $Text = $cite->{'rest_text'};
 
        if  ($Text =~ s/[,;. ]\s*(?:volume|vol|v)?\.?\s*(\d+)\s*[ ,;]\s*(?:n|no|issue|\#)\.?\s*(\d+)\b/$1/is) {
 
                $cite->{'volume'} = $2;
                $cite->{'issue'}  = $3;
                $cite->{'jnl_epos'} = length($`);
                $cite->{'rest_text'} = $Text;
                return 1
                }
        else { return 0}
        }

sub find_vol_supl {
        my $cite = shift;
        my $Text = $cite->{'rest_text'};
 
        if  ($Text =~ s/(\s|,|;|\.)\s*(?:volume|vol|v)?\.?\s*(\d+)\s*[\s,;]\s*(?:supl|supplement)\.?\s*(\d+)\b/$1/is) {
 
                $cite->{'volume'} = $2;
                $cite->{'supl'}  = $3;
                $cite->{'jnl_epos'} = length($`);
                $cite->{'rest_text'} = $Text;
                }
        }


sub find_vol {
        my $cite = shift;
        my $Text = $cite->{'rest_text'};

        if ($Text =~ s/[,;:. ]\s*(?:volume|vol)[. ]\s*([a-z]*\d+[a-z]*)\b//i) {
                $cite->{'volume'} = $1;
                $cite->{'rest_text'} = $Text;
                return
                };      

	# "..., Vol9 ..."
        if ($Text =~ s/[,;:. ]\s*(?:volume|vol)(\d+[a-z]*)\b//i) {
                $cite->{'volume'} = $1;
                $cite->{'rest_text'} = $Text;
                return
                };                                                              

	if ($Text =~ s/[,;:. ]\s*(?:volume|vol)(\d+[a-z]*)\b//i) {
		$cite->{'volume'} = $1;
		$cite->{'rest_text'} = $Text; 
		return
		};

	# beware: "Smith, V. 1990, Phys. Rev. A. v. 10 ..."
	while ($Text =~ /[,;. ]\s*V\s*[. ]\s*([a-z]*\d+[a-z]*)\b/ig){
		my $Guess_vol = $1;
		next if ($Guess_vol =~ /(19|20)\d\d/);

		$cite->{'volume'} = $Guess_vol;
		$Text =~ s/[,;. ]\s*V\s*[. ]\s*[a-z]*\d+[a-z]\b//i;
		$cite->{'rest_text'} = $Text;
		return  
		};

	# "... v10, ..."
        if ($Text =~ s/[,;:. ]\s*V(\d+[a-z]*)\b//i) {
                $cite->{'volume'} = $1;
                $cite->{'rest_text'} = $Text;
                return
                };                                                              
        } 

sub find_issue {
        my $cite = shift;
        my $Text = $cite->{'rest_text'};

	if ($Text =~ s/[,;:. ]\s*(?:number|issue|num|no|Nr|\#)[. ]\s*([a-z]*\d+[a-z]*)\b//i) {
		$cite->{'issue'} = $1;
		$cite->{'rest_text'} = $Text; 
		return
                };

	# e.g. " ...No10, ..."
	if ($Text =~ s/[,;:. ]\s*(?:number|issue|num|no|Nr)(\d+[a-z]*)\b//i) {
		$cite->{'issue'} = $1;
                $cite->{'rest_text'} = $Text;
                return
                };    

	while ($Text =~ /[,;:. ]\s*N\s*[. ]\s*([a-z]*\d+[a-z]*)\b/ig){ 
		my $Guess_issue = $1;
		next if ($Guess_issue =~ /(19|20)\d\d/); 

		$cite->{'issue'} = $Guess_issue;
		$Text =~ s/[,;. ]\s*N\s*[. ]\s*[a-z]*\d+[a-z]*\b//i;
		return
		};

	        if ($Text =~ s/[,;:. ]\s*(?:n|\#|\#\s+)(\d+[a-z]*)\b//i) {
                $cite->{'issue'} = $1;
                $cite->{'rest_text'} = $Text;
                return
                };
                         

}

sub find_supplement {
	my $cite = shift; 
	my $Text = $cite->{'rest_text'};

	if ($Text =~ s/[,;:. ]\s*(?:suppl|supplement)\.?\s*(\d+)\b//i) {
		$cite->{'supl'} = $1;
		$cite->{'num_of_fig'} = $cite->{'num_of_fig'} - 1;
		$cite->{'rest_text'} = $Text
		}
	}


sub find_url {
	my $cite = shift;
	my $Text = $cite->{'rest_text'};

	if ($Text =~ s/\b(http:\/\/[^\s]+)/ /i){
		my $url = $1;
		$url =~ s/\W*$//;
		$cite->{'targetURL'} = $url;
		$cite->{'rest_text'} = $Text;
		return 1
		};

	if ($Text =~ s/\b(http:\/\/[^\s>]+)(?:\s|$)/ /i){
                $cite->{'targetURL'} = $1;
                $cite->{'targetURL'} =~ s/[.,;]$//;
                $cite->{'rest_text'} = $Text;
		return 1
		};

	return 0
	}


sub find_page {
        my $cite = shift;
        my $Text = $cite->{'rest_text'};

	# keep the order of the pattern matching.

	# '... p.20, p 20, ...'
        if ($Text =~ s/[,;:. ]\s*(?:pages|page|pp)\s*[.# ]\s*([a-z]*\d+[a-z]*)\b//i) {
                $cite->{'spage'} = $1;
                $cite->{'rest_text'} = $Text;
		return
                };

	# " ... pp20, ..." 
        if ($Text =~ s/[,;:. ]\s*(?:pages|page|pp)(\d+[a-z]*)\b//i) {
                $cite->{'spage'} = $1;
                $cite->{'rest_text'} = $Text;
                return
                };                                                              

	# ... p. 1990-1993
        if  ($Text =~ s/[,;. ]\s*(?:p)\s*[. ]\s*
                     ([a-z]*\d+[a-z]*)\s*\-\s*[a-z]*d+[a-z]*\b//xi) {
	
		$cite->{'spage'} = $1; 
        	$cite->{'rest_text'} = $Text;        
		return
                };     

	# Beaware "Smith P. 1990, ..., p. 100"
	while ($Text =~ /[,;. ]\s*p\s*[. ]\s*([a-z]*\d+[a-z]*)\s*(?!\-)/ig){
		my $Guess_page = $1;
		next if ($Guess_page =~ /(19|20)\d\d/);

		$cite->{'spage'} = $Guess_page;
		$Text =~ s/[,;. ]\s*p\s*[. ]\s*[a-z]*\d+[a-z]*\s*(?!\-)//i;
		$cite->{'rest_text'} = $Text;
		return
		};

        # " ... p20, ..."
        if ($Text =~ s/[,;:. ]\s*p(\d+[a-z]*)\b//i) {
                $cite->{'spage'} = $1;
                $cite->{'rest_text'} = $Text;
                return
                };                                                              
        }


sub find_year {
        my $cite = shift;
 
        return 1 if ($cite->{'year'});
 
        my $Text = $cite->{'rest_text'};
 
        # priority is given to (1989) type.
        if ($Text =~ s/\(((19|20)\d\d)\w?\)//) {
                $cite->{'year'} = $1;
                $cite->{'rest_text'} = $Text;
                return 1
                };
 
        # year like numbers not before/after a '-'
        # e.g. 1966-1988 may indicate a page range.
        if ($Text =~ /[^\w\-"]((19|20)\d\d)\w?([^\w\-"]|$)/i) {
 
                $cite->{'year'} = $1;
                $Text =~ "\Q$` $'\E";
                $cite->{'rest_text'} = $Text;
                return 1
                };
 
        return 0;
        }

# Apt'e, C., et al. ACM Transactions on Information Systems 12, 3, 233-251
sub guess_vol_no_pg {
	my $cite = shift;
        return 1 if ($cite->{'volume'} and $cite->{'issue'} and
                     $cite->{'spage'});
        return 0 if ($cite->{'num_of_fig'} < 3);

	my $Text = $cite->{'rest_text'};

        # change (1,1) alike to ().
        $Text =~ s/\(\d+\s*,\s*\d+\s*\)/\(\)/g;        
	$Text =~ s/\(\d+\s*;\s*\d+\s*\)/\(\)/g;

        if ($Text =~
          /[^\w\/.-](?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?) # volume
           [^\w\/.-]+(?:n|no|number|issue|\#)?\.?\s*([a-z]*?\d+[a-z]*?) # issue
           [^\w\/.-]+(?:pages|page|pp|p)?\.?
                \s*([a-z]*?\d+[a-z]*?)(?:\s*-\s*[a-z]*?\d+[a-z]*?)?
              (\W*|$)/xi) {
 
                $cite->{'volume'} = $1;
                $cite->{'issue'}  = $2;
                $cite->{'spage'}  = $3;
                $cite->{'jnl_epos'} = length($`) + 1;
 
                return 1  
	};

	return 0

}


# '15:190' (15A:190-195, 14-15:190-180, or "Astrophys. J. 8, 103");
# Called this after '{find_vol_{no}_pg_year}' failed.
sub guess_vol_pg {
        my $cite = shift;
        return 1 if ($cite->{'volume'} and $cite->{'spage'});
        return 0 if ($cite->{'num_of_fig'} < 2);
 
        my $Text = $cite->{'rest_text'};

        # change (1,1) alike to ().
        $Text =~ s/\(\d+\s*,\s*\d+\s*\)/\(\)/g;
        $Text =~ s/\(\d+\s*;\s*\d+\s*\)/\(\)/g;    

        # 15A:190-195 type
        if ($Text =~ s/[^\w\/.-]([a-z]*?\d+[a-z]*?)\s*:\s*([a-z]*?\d+[a-z]*?)\s*
                      (-\s*[a-z]*?\d+[a-z]*?)?(\W|$)/$4/xi) {
                $cite->{'volume'}  = $1;
                $cite->{'spage'} = $2;
                $cite->{'jnl_epos'} = length($`) + 1;

                $cite->{'rest_text'} = $Text;
                return 1
                };

	# Astrophys. J. Lett., 452, p.L91-L93
	# AIP, vol 307, p.117, New York (1994). 
	# Pub. Astron. Soc. Japan, 2000,  p.52  
        if ($Text =~ 
                 /[^\w\/.-](?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?) # volume
                 [^\w\/.-]*,\s*(?:p|pp|page|pages)[. ]\s*([a-z]*?\d+[a-z]*?)\s*
                 (-\s*[a-z]*?\d+[a-z]*?)?(?:\W|$)/xi) {

		my $Guess_vol = $1;
		$cite->{'spage'} = $2;
		my $Guess_jnl_epos = length($`) + 1; # prematch
 
		if ($Guess_vol =~ /^(19|20)\d\d[a-z]?$/i) {
			$cite->{'year'}   = $Guess_vol;
			$cite->{'rest_text'} =~
			  s/([^\w\/.-])(?:volume|vol\.?|v\.?)?\s*[a-z]*?\d+[a-z]*?\s*,\s*(?:p|pp|page|pages)\s*\.?[a-z]*?\d+[a-z]*?\s*(-\s*[a-z]*?\d+[a-z]*?)?(\W|$)/$1/i;
			return 0
			};
                $cite->{'volume'} = $Guess_vol;
		$cite->{'jnl_epos'} = $Guess_jnl_epos;
		$cite->{'rest_text'} =~
                       s/([^\w\/.-])[a-z]*?\d+[a-z]*?\s*,\s*(?:p|pp|page|pages)\s*\.?[a-z]*?\d+[a-z]*?\s*(-\s*[a-z]*?\d+[a-z]*?)?(\W|$)/$1/i;
                return 1
                };

	# Elias, J. 1994, NOAO Newsletter, No. 37, 1 
        if ($Text =~
                 /[^\w\/.-](?:n|no|num|issue)[. ]\s*([a-z]*?\d+[a-z]*?) # volume
                 [^\w\/.-]*,\s*(?:p|pp|page|pages)?\.?\s*([a-z]*?\d+[a-z]*?)\s*
                 (-\s*[a-z]*?\d+[a-z]*?)?(?:\W|$)/xi) {
 
                $cite->{'issue'} = $1;
                $cite->{'spage'} = $2;
                $cite->{'jnl_epos'} = length($`) + 1; # prematch           
		$cite->{'rest_text'} =~
		     s/([^\w\/.-])(?:n|no|num|issue)[. ]\s*[a-z]*?\d+[a-z]*?[^\w\/.-]*,\s*(?:p|pp|page|pages)?\.?\s*([a-z]*?\d+[a-z]*?)\s*(-\s*[a-z]*?\d+[a-z]*?)?(?:\W|$)/$1/i;
		return 1
		};

	# match page range.
	# Phys. Rev. A 4, 52-60 
	# Pub. Astron. Soc. Japan, 1998, 52-60
        if ($Text =~ /[^\w\/.-]([a-z]*?\d+[a-z]*?)     # volume or year
                      [^\w\/.-]*[, ]\s*([a-z]*?\d+[a-z]*?)\s*	    # pages
                      -\s*[a-z]*?\d+[a-z]*?(?:[^\w-]|$)/xi) {

                my $Guess_vol  = $1;
                $cite->{'spage'} = $2;
                my $Guess_jnl_epos = length($`) + 1; # prematch
		    
                if ($Guess_vol =~ /^(19|20)\d\d[a-z]?$/i) {
                        $cite->{'year'}   = $Guess_vol;
			$cite->{'rest_text'} =~
			  s/([^\w\/.-])[a-z]*?\d+[a-z]*?\s*[, ]\s*([a-z]*?\d+[a-z]*?)\s*-\s*[a-z]*?\d+[a-z]*?(?:[^\w\/.-]|$)/$1/i;
			return 0
			};
                $cite->{'volume'} = $Guess_vol;
		$cite->{'jnl_epos'} = $Guess_jnl_epos;
                $cite->{'rest_text'} =~ s/([^\w\/.-])[a-z]*?\d+[a-z]*?\s*,\s*([a-z]*?\d+[a-z]*?)\s*-\s*[a-z]*?\d+[a-z]*?(?:[^\w\/.-]|$)/$1/i;

                return 1
                }; 

	# Phys. Rev. B 38, 2297. (Phys. Rev. B 38 2297) 
	# Pub. Astron. Soc. Japan, 2000, 52.
        if ($Text =~ /[^\w\/.-]([a-uw-z]*?\d+[a-z]*?)
              [^\w\/.-]*[, ]\s*([a-z]?\d+[a-z]?)(?:[^\w\/.-]|$)/xi) {

		my $Guess_vol  = $1; 
		my $Guess_page = $2;
                $cite->{'jnl_epos'} = length($`) + 1;

                if ($Guess_vol =~ /^(19|20)\d\d[a-z]?$/i) {
                        $cite->{'year'}   = $Guess_vol;
                } else {
                        $cite->{'volume'} = $Guess_vol;
                };

                if ($Guess_page =~ /^(19|20)\d\d[a-z]?$/i) {
                        $cite->{'year'} = $Guess_page;
                } else {
                        $cite->{'spage'} = $Guess_page;
                };
                 
                $cite->{'rest_text'} =~
                    s/([^\w\/.-])[a-z]*?\d+[a-z]*?[^\w\/.-]*[, ]\s*[a-z]*?\d+[a-z]*?(?:[^\w\/.-]|$)/$1/i;
		return 1 if ($cite->{'volume'} and $cite->{'spage'});
                return 0 
                };
 
        return 0
        }; 

#
# G. Smith and H. Gray; Pub. Astron. Soc. Japan, 2000, vol. 52
# To find $cite->{'jnl_epos'} currectly. Note that '2000' may be
# regarded as the journal name (by subroutine find_vol).
sub guess_vol_year {
        my $cite = shift;
        return 0 if ($cite->{'num_of_fig'} < 2);
 
        my $Text = $cite->{'rest_text'};

        # change (1,1) alike to ().
        $Text =~ s/\(\d+\s*,\s*\d+\s*\)/\(\)/g;
        $Text =~ s/\(\d+\s*;\s*\d+\s*\)/\(\)/g;    
 
        if ($Text =~
             /[^\w\/.-]\(?((19|20)\d\d)\w?\)?[^\w\/.-]*
             (?:volume|vol|v)\W*([a-oq-z]*?\d+[a-z]*?)(\W|$)/xis) {
 
                $cite->{'year'} = $1;
                $cite->{'volume'}  = $3;
                $cite->{'jnl_epos'} = length($`);
 
                return 1
                };  

	# be aware: "Workshop on ..., p30 (1999)."
	if ($Text =~
	     /[^\w\/.-](?:volume|vol|v)?\W*([a-oq-z]?\d+[a-z]?)
	      [^\w\/.-]+\(?((19|20)\d\d)\w?\)?(\W|$)/xis) {
		$cite->{'volume'} = $1;
		$cite->{'year'}   = $2;
		$cite->{'jnl_epos'} = length($`);

		return 1
		};
	       
        return 0
        };
 
sub find_vol_no_pg_year {
        my $cite = shift;
        return 1 if ($cite->{'volume'} and $cite->{'issue'} and
                     $cite->{'spage'} and $cite->{'year'});
        return 0 if ($cite->{'num_of_fig'} < 4);
 
        my $Text = $cite->{'rest_text'};

        # change (1,1) alike to ().
        $Text =~ s/\(\d+\s*,\s*\d+\s*\)/\(\)/g;
        $Text =~ s/\(\d+\s*;\s*\d+\s*\)/\(\)/g;    

        # Keep the following order of texting $Text;
        # Important: check 'year' at the end first.
 
        # (A.1):
        # 'year' is at the end, within bracket.
        # ..., v.517, no. 1, p.190-200, (1999)
        # ..., 11(2), 100-105, (1999) 
        if ($Text =~
	  /[^\w\/.-](?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?) # volume
           [^\w\/.-]+(?:n|no|number|issue|\#)?\.?\s*([a-z]*?\d+[a-z]*?) # issue
           [^\w\/.-]+(?:pages|page|pp|p)?\.?
                \s*([a-z]*?\d+[a-z]*?)(?:\s*-\s*[a-z]*?\d+[a-z]*?)?
              \W*\(((19|20)\d\d)[a-z]*?\)(\W|$)/xi) {
 
                $cite->{'volume'} = $1;
		$cite->{'issue'}  = $2;
                $cite->{'spage'}  = $3;
                $cite->{'year'}   = $4;
                $cite->{'jnl_epos'} = length($`) + 1;
 
                return 1
            };
 
        # (A.2) 'year' is in the middle, within bracket.
        #  ..., 4(2), (1999), 100-105
        if ($Text =~
          /[^\w\/.-](?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?)   # volume
           [^\w\/.-]+(?:n|no|number|issue|\#)?\.?\s*([a-z]*?\d+[a-z]*?) # issue
           \W*\(((19|20)\d\d)[a-z]*?\)                           # year
              \W*(?:pages|page|pp|p)?\.?\s*([a-z]*?\d+[a-z]*?)(\W|$)/xi) {
 
                $cite->{'volume'} = $1;
		$cite->{'issue'}  = $2;
                $cite->{'year'}   = $3;
                $cite->{'spage'}  = $5;
                $cite->{'jnl_epos'} = length($`) + 1;

                return 1
                };
 
        # (A.3.1) 'year' is at the beginning, within bracket, after
	# journal title;
        # ...., (1999), 517, no. 1, p.190-200
        if ($Text =~
	  /\(((19|20)\d\d)[a-z]*?\)[,.;\s:]*            # year
           (?:volume|vol|v)?\.?\s*([a-z]*?\d+[a-z]*?)  # volume
           [^\w\/.-]+(?:n|no|number|issue|\#)?\.?\s*([a-z]*?\d+[a-z]*?) # issue
           [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]*?\d+[a-z]*?)(\W|$)/ix)
        {
                $cite->{'year'}   = $1;
                $cite->{'volume'} = $3;
                $cite->{'issue'}  = $4;
                $cite->{'spage'}  = $5;
		$cite->{'jnl_epos'} = length($`);

                return 1;
                };

        # (A.3.2) 'year' is at the beginning, within bracket, before
	# journal title;
        # ..., (1999),..., 517, no. 1, p.190-200
        if ($Text =~
          /\(((19|20)\d\d)[a-z]*?\)                   # year
	  ([^(]+?)
	  [^\w\/.-](?:volume|vol|v)?\.?\s*([a-z]*?\d+[a-z]*?)  # volume
          [^\w\/.-]+(?:n|no|number|issue|\#)?\.?\s*([a-z]*?\d+[a-z]*?) # issue
          [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]*?\d+[a-z]*?)(\W|$)/ix){
                $cite->{'year'}   = $1;
                $cite->{'volume'} = $4;
                $cite->{'issue'}  = $5;
                $cite->{'spage'}  = $6;

	#	$cite->{'jnl_spos'} = length($`);
	#	$cite->locate_jnl_epos();
		$cite->{'jnl_epos'} = length($`) + length($1) +
				      length($3);
                return 1;
                };  
 
 
        # (B.1):
        # 'year' is at the end, but not in bracket;
        # ..., v.517, no. 1, p.190-200, 1999
        # ...,   517, no. 1, p.190-200, 1999
        if ($Text =~
	  /[^\w\/.-](?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?)   # volume
           [^\w\/.-]+(?:n|no|number|issue|\#)?\.?\s*([a-z]*?\d+[a-z]*?) # issue
           [^\w\/.-]+(?:pages|page|pp|p)?\.?
                \s*([a-z]*?\d+[a-z]*?)(?:\s*-\s*[a-z]*?\d+[a-z]*?)?
           [^\w(:\/.-]+?((19|20)\d\d)[a-z]?\s*(?![)-])/xi) { 
 
                $cite->{'volume'} = $1;
                $cite->{'issue'}  = $2;
                $cite->{'spage'}  = $3;
                $cite->{'year'}   = $4;
                $cite->{'jnl_epos'} = length($`) + 1;
 
                return 1
                };
 
 
        # (B.2): 'year' is in the middle, but not in bracket.
        #  4(2), 1999, 100-105
        if ($Text =~
	  /[^\w\/.-](?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?)   # volume
           [^\w\/.-]+(?:n|no|number|issue|\#)?\.?\s*([a-z]*?\d+[a-z]*?) # issue
           [^\w(:\/.-]+?\s*((19|20)\d\d)[a-z]?                      # year
           \s*[^\w\/.)-]+?\s*(?:pages|page|pp|p)?\.?\s*([a-z]*?\d+[a-z]*?)(\W|$)/xi) {
 
                $cite->{'volume'} = $1;
                $cite->{'issue'}  = $2;
                $cite->{'year'}   = $3;
                $cite->{'spage'}  = $5;
                $cite->{'jnl_epos'} = length($`) + 1;
 
                return 1
                };
 
        # (B.3.1): 'year' is at beginning, not in bracket, after jtitle;
        # ..., 1999, v.517, no. 1, p.190-200
        #   " ... 1890-1999", MNRAS, 2000, 4:1, p 1990
        if ($Text =~
             /[^"(\/.-]\s*((19|20)\d\d)[a-z]?[,;\.\s]+     # year
              (?:volume|vol|v)?\.?\s*([a-z]*?\d+[a-z]*?)  # volume 
	       [^\w\/.-]+?(?:n|no|number|issue|\#)?\.?\s*([a-z]*?\d+[a-z]*?)
              [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]*?\d+[a-z]*?)(\W|$)/ix)
        {
                $cite->{'year'}   = $1;
                $cite->{'volume'} = $3;
		$cite->{'issue'}  = $4;
		$cite->{'spage'}  = $5;
		$cite->{'jnl_epos'} = length($`) + 1;
                return 1
                };
 
        # (B.3.2): 'year' is at beginning, not in bracket, before jtitle;
        # 1999, ..., v.517, no. 1, p.190-200
        # 1999, ...,   517, no. 1, p.190-200
        # 1999, ..., 517(1), 190-200
        # NB: 1999, "... 1.5 factor ....", 517(1), 190-200
        # NB: B. Greene, editors, "Fields, Strings and Duality, TASI 1996",
        #     pages 421-540, World Scientific, 1997.
        #   " ... 1890-1999", MNRAS, 2000, 4:1, p 1990
        if ($Text =~
             /(?:^|[^"(\/.-])\s*((19|20)\d\d)[a-z]?     # year
	      [^\w:")(\/-][^(]*?
	      [^\w\/.-](?:volume|vol|v)?\.?\s*([a-z]*?\d+[a-z]*?)  # volume
              [^\w\/.-]+?(?:n|no|number|issue|\#)?\.?\s*([a-z]?\d+[a-z]?)
              [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]*?\d+[a-z]*?)(\W|$)/ix)
        {
                $cite->{'year'}   = $1;
                $cite->{'volume'} = $3;
                $cite->{'issue'}  = $4;
                $cite->{'spage'}  = $5;

		$cite->{'jnl_spos'} = length($`);
		$cite->locate_jnl_epos(); 
                return 1
                }; 
        return 0
        };
            

# For cases where 'vol, page, year' can be identified correctly.
sub find_vol_pg_year {
        my $cite = shift;
        return 1 if ($cite->{'volume'} and $cite->{'spage'} and
                     $cite->{'year'});
        return 0 if ($cite->{'num_of_fig'} < 3);
 
        my $Text = $cite->{'rest_text'};

        # change (1,1) alike to ().
        $Text =~ s/\(\d+\s*,\s*\d+\s*\)/\(\)/g;
        $Text =~ s/\(\d+\s*;\s*\d+\s*\)/\(\)/g;    
 
        # (A.1) 'year' is at the end, within bracket.
        # ......, vol.8:100, (1999)
        # ......,     8:100, (1999)
        #                       ~~~~
        if ($Text =~
          /(?:^|[^\w\/.-])(?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?) # volume
           [^\w\/.-]+(?:pages|page|pp|p)?\.?
             \s*([a-z]?\d+[a-z]?)(?:\s*-\s*[a-z]?\d+[a-z]?)?
             \W*\(((19|20)\d\d)[a-z]?\)(\W|$)/xi) {
 
                $cite->{'volume'}  = $1;
                $cite->{'spage'} = $2;
                $cite->{'year'} = $3;
                $cite->{'jnl_epos'} = length($`) + 1;
 
                return 1
                };
 
        # (A.2) 'year' is in the middle, within bracket.
        # ......, 8, (1999), 100-105
        if ($Text =~
          /(?:^|[^\w\/.-])(?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?) # volume
           \W*\(((19|20)\d\d)[a-z]?\)                  # year
             \W*(?:pages|page|pp|p)?\.? 
               \s*([a-z]?\d+[a-z]?)(?:\s*-\s*[a-z]?\d+[a-z]?)?(\W|$)/xi) {
 
                $cite->{'volume'}  = $1;
                $cite->{'year'} = $2;
                $cite->{'spage'} = $4;
                $cite->{'jnl_epos'} = length($`) + 1;
 
                return 1
                }; 
 
        # (A.3.1.) 'year' is at beginning, within bracket, after jtitle;
        # ......, (1999) 517, 190-200
        if ($Text =~
          /\(((19|20)\d\d)[a-z]?\)[,;\.\s]*       # year
           (?:volume|vol|v)?\.?\s*([a-z]*?\d+[a-z]*?)  # volume
           [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]?\d+[a-z]?)(\W|$)/ix){
                $cite->{'year'} = $1;
                $cite->{'volume'} = $3;
                $cite->{'spage'}= $4;
		$cite->{'jnl_epos'} = length($`);
 
                return 1;
                };

        # (A.3.1.1) 'year' is at beginning, within bracket, after jtitle;
        # not 'vol', buy 'No.@, e.g."..., (1999) No. 517, 190-200
        if ($Text =~
          /\(((19|20)\d\d)[a-z]?\)[,;\.\s]*       # year
           (?:number|no|n)\.?\s*([a-z]*?\d+[a-z]*?)  # volume
           [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]?\d+[a-z]?)(\W|$)/ix){
                $cite->{'year'} = $1;
                $cite->{'volume'} = $3;
                $cite->{'spage'}= $4;
                $cite->{'jnl_epos'} = length($`);
 
                return 1;
                };                                                              
 

        # (A.3.2.) 'year' is at beginning, within bracket, before jtitle;
        # ..., (1999),..., 517, p.190-200
        if ($Text =~
          /\(((19|20)\d\d)[a-z]?\)        # year
           [^(]+?
           [^\w\/.-](?:volume|vol|v)?\.?\s*([a-z]*?\d+[a-z]*?)  # volume
           [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]?\d+[a-z]?)(\W|$)/ix){
                $cite->{'year'}   = $1;
                $cite->{'volume'} = $3;
                $cite->{'spage'}  = $4;

		$cite->{'jnl_spos'} = length($`);
		$cite->locate_jnl_epos();
                return 1;
                };  

        # (B.1) 'year' is at the end, but not in bracket.
        # ......, vol.8:100, 1999
        # ......,     8:100, 1999
        # NB: ..., 1999, 8(1900)
        #                  ~~~~
        if ($Text =~
	  /[^\w\/.-](?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?) # volume
           [^\w\/.-]+(?:pages|page|pp|p)?\.?
                \s*([a-z]?\d+[a-z]?)(?:\s*-\s*[a-z]?\d+[a-z]?)? # page
           [^\w:(\/.-]+\s*((19|20)\d\d)[a-z]?\s*(?![)-])/xi) {
 
                $cite->{'volume'}  = $1;
                $cite->{'spage'} = $2;
                $cite->{'year'} = $3;
                $cite->{'jnl_epos'} = length($`) + 1;
 
                return 1
                };
 
        # (B.2) 'year' is in the middle, but not in brackets;
        # ... 8, 1999, p.100
        # ... 8, 1999, 100-105
        if ($Text =~
	  /[^\w\/.-](?:volume|vol\.?|v\.?)?\s*([a-z]*?\d+[a-z]*?)  # volume
           [^\w:(\/.-]+?\s*((19|20)\d\d)[a-z]?                     # year   
           [^\w\/.)-]+(?:pages|page|pp|p)?\.?\s*([a-z]?\d+[a-z]?)(\W|$)/xi)
        {
                $cite->{'volume'}  = $1;
                $cite->{'year'} = $2;
                $cite->{'spage'} = $4;
                $cite->{'jnl_epos'} = length($`) + 1;
 
                return 1
                };

        # (B.3.1) 'year' is at the beginning,not in bracket, after jtitle;
        # ..., 1999, 8, p1990
        if ($Text =~
          /[^\w\/.(-]\s*((19|20)\d\d)[a-z]?[,;\.\s]+
           (?:volume|vol|v)?\.?\s*([a-z]*?\d+[a-z]*?)  # volume
           [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]?\d+[a-z]?)(\W|$)/ix){
                $cite->{'year'}   = $1;
                $cite->{'volume'} = $3;
                $cite->{'spage'}  = $4;
                $cite->{'jnl_epos'} = length($`)+1;
                return 1
                }; 

        # (B.3.1.1) 'year' is at the beginning,not in bracket, after jtitle;
        # no 'vol', but 'no.' e.g. ..., 1999, No. 8, p1990
        if ($Text =~
          /[^\w\/.(-]\s*((19|20)\d\d)[a-z]?[,;\.\s]+
           (?:number|no|n)\.?\s*([a-z]*?\d+[a-z]*?)  # no volume, but issues
           [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]?\d+[a-z]?)(\W|$)/ix){
                $cite->{'year'}   = $1;
                $cite->{'issue'} = $3;
                $cite->{'spage'}  = $4;
                $cite->{'jnl_epos'} = length($`)+1;
                return 1
                };                                                              

 
        # (B.3.2) 'year' is at beginning, not in bracket, before jtitle;
        #  1999, ..., 8(100)
        if ($Text =~
	  /((^|[^"\/.(-])\s*)(((19|20)\d\d)[a-z]?)	       # year
	   ([^\w:")(\/][^(]*?)
           [^\w\/.-](?:volume|vol|v)?\.?\s*([a-z]*?\d+[a-z]*?)  # volume
           [^\w\/.-]+(?:pages|page|pp|p)?\.?\s*([a-z]?\d+[a-z]?)(\W|$)/ix){
                $cite->{'year'}   = $4;
                $cite->{'volume'} = $7;
                $cite->{'spage'}  = $8;
	
		# $cite->{'jnl_spos'} = length($`);	
		# $cite->locate_jnl_epos();
		$cite->{'jnl_epos'} = length($`) + length($1) + 
                                      length($3) + length($6);
                return 1
                };
 
        return 0
        } 


# This subroutine is only called when the journal title is between
# 'year' and 'vol/page', e.g. (a lot in astro-ph/)
# Barnes, J., Efstathiou, G., 1987, ApJ, 319, 575
# For other cases, the cite{'jnl_epos'} is determined while trying to
# find out the vol, page, year, i.e. in 'find_vol_no_pg_year' kind
# of subroutines.
#
sub locate_jnl_epos {
 
        my $cite = shift;
	my $sPos = $cite->{'jnl_spos'};
        my $Text = substr($cite->{'rest_text'}, $sPos);
 
       # $Text =~ s/(\W+)(?:pages|page|pp|p)\W*(\d+)/$1$2/;
       # $Text =~ s/-\d+[a-z]*?//;  # pp100-105
 
        # Before 'volume'
        if ($Text =~ /\b(?:volume|vol\.?|v\.?)\s*[a-z]*?\d+[a-z]*?(?![.0-9])/i) {
                $cite->{'jnl_epos'} = length($`) + $sPos;
                return 1
                }; 

	# (1997) Phys. Rev. E56, No.3, 2875 
	# (1997) Phys. Rev. A50, p.160
	if ($Text =~ /
               [^\w\/.-](?:volume|vol\.?|v\.?)?\s*[a-z]*?\d+[a-z]*? # volume
               [^\w\/.-]+(?:n |n.|no |no.|number |issue |\#|p |p.|pp.|page )\s*[a-z]*?\d+[a-z]*?
               (?:\W|$)/xi) {
		$cite->{'jnl_epos'} = length($`) + $sPos + 1 ;
		return 1
		};

        # Before any two consecutive numbers, but not '123-127' style page.
        #   Bertelli, G., 1999, ApJ, 517(1), ....
        #   ApJ, 517:1, ...
        #   ApJ, 517:367-380.
        #Beaware: J.K. Lanyi. 1999. Structure of bacteriorhodopsin at 1.55
        #         angstrom resolution J. Mol. Bio. 291:899-911        ~~~~!
        if ($Text =~ /[^\w\/.-][a-z]*?\d+[a-z]*?\s*[,:(\s]\s*
                       [a-z]?\d+[a-z]?(\W|$)/xi) {
                $cite->{'jnl_epos'} = length($`) + $sPos + 1;
                return 1
                };
 
        return 0
        };


sub find_jnl_name {
        my $cite = shift;
 
        return 1 if ($cite->{'jtitle'});
        return 0 if (! $cite->{'jnl_epos'});

        # Assumption: journal name usually starts after a ',;'
        # or " which is used to enclose the article title,
        # and does not contain those symbols (i.e. ,;")
        #
        my $Text = substr($cite->{'rest_text'}, 0, $cite->{'jnl_epos'});
	my $Guess_jnl;

	# Linden, N., et al. quantph/9711016 and Fortsch. Phys. 46, 567 (1998)
	#if ($Text =~ m{[^/]+/\w+\s*(.+)$}) {
	#	$Text = $1 
	#	};

   LOOP:
	# remove trailing symbols   
	$Text =~ s/\s*[,;":\/\[\(]*\s*$//s;  

	# ignore anything in brackets (head/tail position)
	$Text =~ s/\W*\([^\)]+\)?\W*$//;
	$Text =~ s/^\s*\([^\)]+\)\W+//;

	return 0 if ($Text eq '');

	# quite many citations are like this:
	# "P. Reiter, et al:Phys. Rev. Lett. 82 (1999) 509"
	# hard to separate name from journal title. Other cases
	# are: '..., J.PHY.G:NUCL.PART.PHY.'. Have to compramise.
	if ($Text =~ /([^,;":?\/\[]+)$/) {
                $Guess_jnl = $1;
		$Guess_jnl =~ s/^['`]?\s*//;
                $Guess_jnl =~ s/\s+$//; 

		# ignore things in brackets
		$Guess_jnl =~ s/\W*\([^\)]+\)?\W*$//;  
		$Guess_jnl =~ s/^\([^\)]+\)\W*//;

		# journal name should begin and contain alphabet, 
                # not only numbers; and should be longer than one
                # character. First remove 'year'
		$Guess_jnl =~ s/^.*?\(?(19|20)\d\d\w*\)?\W*//;
		if ($Guess_jnl =~ /^[a-z]\W*$/i) {
                        $Text =~ s/[^,;":?\/\[]+$//;
                        goto LOOP
                        };      

		# No captital letters
		if ($Guess_jnl !~ /[A-Z]/) {
			$Text =~ s/[^,;":?\/\[]+$//; 
			goto LOOP
			};

		# "Report of ... Conf.:1. Introduction. Canadian Medical Association Journal"
                if ($Guess_jnl !~ /^[a-z]+/i) {
			my @gWords = split(/\s+/, $Guess_jnl);

			if (scalar(@gWords) <= 3) { 
                        	$Text =~ s/[^,;":?\/]+$//;
                        	goto LOOP
				}
                        };

		$Text = $Guess_jnl;
		}
	else {
		$Text =~ s/^[`']?\s*//;
		$Text =~ s/\s*$//;

		# 'jtitle' is after 'year' (other cases are dealt by
        	# $cite->{'jnl_epos'} in 'find_vol_{no}_pg_year()'..
        	if ($Text =~ /[,\s\(]+(19|20)\d\d[,\s\)]+\s*/) {
                	$Text = $'
                	};
		};
 
	my $end_dot = 0;
	$end_dot = 1 if ($Text =~ /\.$/);
        my @Title_words = ();
        my @Words = ();
	my $i = 0;

        # process from the end of the $Text to see if
        # a $Parts[$i] is (still) a part of a journal name.  
        my @Parts = split(/\s*\.\s*/, $Text);
        for ($i = $#Parts; $i>=0; $i--) {
		next if ($Parts[$i] !~ /[a-z]/i);

		# author name may be mixed into the journal title 
		# e.g. "Popescu S. and G. A. Sudbery. J. of Phy ..."
		if ($i > 0 and $Parts[$i-1] =~ /^([A-Z][a-z]* )*and\s+[A-Z]$/) {
			last 
		};
		if ($i > 1 and $Parts[$i-2] =~ /^([A-Z][a-z]* )*and\s+[A-Z]$/) {
			last if ($Parts[$i-1] =~ /^[A-Z]$/);
		};

		# author name may be mixed into the journal title
		# e.g. "and Sudbery A. Multi-particle ..."
		if ($i > 0 and $Parts[$i] =~ /^[A-Z]$/) {
			# less than 4 words.
			if ($Parts[$i-1] =~ /^\S+\s+\S+(\s+\S+){0,2}$/ and	
			    $Parts[$i-1] =~ /^(and )?[A-Z].+?[A-Z]$/){
				last
				}
			};

                push(@Title_words, $Parts[$i]);
		last if $i == 0;   # necessary test

		last if ($Parts[$i-1] =~ /et\s+al$/i);
		last if ($Parts[$i-1] =~ /^\s*\d+$/);

                @Words = split(/\s+/, $Parts[$i-1]);
		# stop if more than 4 words in $Parts[$i-1],
		# i.e. $Parts[$i-1] seems to contain article title,
		# not the journal name. However, be aware of:
		# "... method for propagating interfaces J. Comput. Phys." 
		# next if (scalar(@Words) <= 2 and
		next if (scalar(@Words) <= 2 and $Parts[$i-1] !~ /^\d/); 

		if (scalar(@Words) <= 4 and
		    $Parts[$i-1] =~ /^([A-Z][a-z]*\s+){0,3}[A-Z][a-z]*$/){
			next
			}; 
 
		my $w = pop(@Words);
		# if ($w =~ /^[A-Z]$/ or $w =~ /^[A-Z][a-z]+$/) {
		# if ($w =~ /^J$/ or $w =~ /^[A-Z][a-z]+$/) {
		if ($w =~ /^J$/){ 
			push(@Title_words, $w)
			};

		last
		};
        if (scalar(@Title_words) == 1) {
                $cite->{'jtitle'} = $Title_words[0]
                }
        else {
                my @Title_words_real = reverse(@Title_words);
                $cite->{'jtitle'} = join('.', @Title_words_real);
             };

	$cite->{'jtitle'} = "$cite->{'jtitle'}\." if ($end_dot == 1);
	 
        # normalise it
        $cite->{'jtitle'} = normalise_journal($cite->{'jtitle'});
        return 1
        };
           


sub full_name {
        my $Text = shift;

	$Text =~ s/(^|s*)Jr[. ]//i;

	return 1 if ($Text =~ /^\s*et al\s*$/i);

	return 0 if ($Text =~/^in /i);
	return 0 if ($Text !~ /[A-Z]/); # no upper case letter
	return 0 if ($Text =~ /\d+/); # $Text contains jtitle.
	return 0 if ($Text =~ / (e-print|archive)s? /i);
	return 0 if ($Text =~ /\b(Collaboration|Review)\b/i);

	my $wCount = word_count($Text);
	return 0 if $wCount > 4;

	# "van Albada" or "van den Bergh" (surname only)
	return 0 if ($Text =~ /^((v\.|von|van|de|den|der)\s+)+\S\S+\s*$/i);
        # "van Buren D"
        return 1 if ($Text =~ /^(von|van|de|den|der)\s+\S\S+\s+([a-z]+\s*)+$/i);    
	# (journal name)
	return 0 if ($Text =~ /\b(Phy\.|Physics|Journal|The)\b/i);
	# "J. Mod. Phys. D";  "Prog.Theor.Phys."
	return 0 if ($Text =~ /^([a-z]+\.\s*)+[a-z]?\s*$/i);
	# "Phys Rev A"
	# return 0 if ($Text =~ /^([a-z][a-z]+(\.| )){2,}[a-z]\.?\s*$/i);
	my @Abbr = ();
	# "Class. Quantum Grav."
	return 0 if (@Abbr = ($Text =~ /\S\S+?\./g) and
		     scalar(@Abbr) >1);
	# "Nuovo Cim. B 44, 1 (1966)."
	return 0 if ($Text =~ /\w\w\w+\./);
	
	# 'W. B. Burton', 'Burton W. B.', 'W B Burton', etc.
	if (has_surname($Text) and
            has_initials($Text) and
	    $wCount >= 1 and
	    $wCount < 5 ) {
		return 1
		};

        # 'Vivek Agrawal', 'Liu Xin' types; hard to distinguish
        #  surname/firstname.
        if ($wCount >= 2 and 
            $wCount <= 3  and
	    no_initials($Text)) {
                return 1
                };   

        return 0
        };
 
sub no_initials {
        my $Text = shift;

	# do not count 'Jr.'	
	$Text =~ s/(\W)Jr\.?\s*$/$1/i;
	return 0 if ($Text =~ /(^| )[a-z]\./i);
	return 0 if ($Text =~ /(^| )[a-z]( |$)/i);

        return 1;
        }; 

sub only_initials {
        my $Text = shift;

	return 0 if ($Text =~ /^[a-z]{2,} /i);
	return 0 if ($Text =~ /\.?\s*[a-z][a-z]+$/i);

        my @Words = split(/[\.\s]/, $Text);
        my $Word;
        foreach $Word (@Words) { return 0 if (length($Word) >= 2)};
 
        return 1
        };

sub is_surname  {
	my ($Text) = @_;
	$Text =~ s/ Jr\W+$//i;

        return 0 if ($Text =~ / (e-print|archive)s? /i);
        return 0 if ($Text =~ /\bCollaboration\b/i);        

	return 1 if ($Text =~ /^(\s*[a-z][\-'a-z]+){1,3}$/i);
	# return 1 if ($Text =~ /^\s*[a-z]+[\-'a-z]+\s*$/i);

	return 0
	}

sub has_surname {
	my $Text = shift;

	return 0 if ($Text =~ /\d+/);
	return 1 if ($Text =~ /^[a-z]{2,}[\s-']/i);
	# return 1 if ($Text =~ /[a-z]{2,}$/i);
	return 1 if ($Text =~ /[\-'\s.][a-z][a-z]+(\s+Jr\.?)?\s*$/i);
	return 0
	}

sub has_initials {
	my $Text = shift;

	return 0 if ($Text =~ /\d+/);
	return 1 if ($Text =~ /^\s*[']?\s*[A-Z](\s|\.|$)/);
	return 1 if ($Text =~ /(^|\s|\.)[a-z](\s|\.|$)/i);
                                                             
	return 0
	}

# mainly used to count 'words' in author names 
sub word_count {
        my ($Text) = @_;

	#$Text =~ s/^[\s.]+//;
	#my @Words = split(/[\s.]+/, $Text);
	# return scalar(@Words);

	$Text =~ s/ (von|van|de|den|der) //g;
	$Text =~ s/^\s+//;
	$Text =~ s/\s+$//;
	my @Words_all = split(/\s+/, $Text);
	# ignore initials in names.
	# e.g. "C.A.R. Sa de Melo" is a name
	my @Words;
	my $W;
	while (@Words_all) {
		$W = shift @Words_all;
		push(@Words, $W) if ($W !~ /^[a-z]\.?$/i);
		};
        return scalar(@Words); 
        };
 
 
#
# To assist accessing of the citation metadata. 
#

sub srcText {
        my $cite = shift;
        return $cite->{'text'};
}


sub list_authors {
	my $cite = shift; 
	return $cite->{'authors'}
}

sub first_author {
        my $cite = shift;
        return $cite->{'aufull'};
}

sub aulast {
	my $cite = shift;
	return $cite->{'aulast'};
}

sub aufirst {
        my $cite = shift;
        return $cite->{'aufirst'};
}

sub auinit {
        my $cite = shift;
        return $cite->{'auinit'};
}                         

# journal title
sub jtitle {
	my $cite = shift;
	return $cite->{'jtitle'};
}

# article title
sub atitle {
	my $cite = shift;
	return $cite->{'atitle'};
}

sub volume {
        my $cite = shift;
        return $cite->{'volume'};
}


sub issue {
        my $cite = shift;
        return $cite->{'issue'};
}

sub supplement {
        my $cite = shift;
        return $cite->{'supl'};
}

sub year {
        my $cite = shift;
        return $cite->{'year'};
}
 
sub startpage {
        my $cite = shift;
        return $cite->{'spage'};
}                                                                               

sub featureID {
	my $cite = shift;
	return $cite->{'featureID'}
}


sub display_metadata_xml {  
    	my $cite = shift;
    	return if (!defined($cite->{'text'}));

	my $root = XML::Element->new('citation');
	my $xml_pi = XML::Element->new('~pi', text=>'xml version="1.0"');

	my $literal = XML::Element->new('literal');
	my $authors = XML::Element->new('authors');
	my $first_author = XML::Element->new('first_author');
	my $title = XML::Element->new('title');
	my $jtitle = XML::Element->new('journaltitle');
	my $volume = XML::Element->new('volume');
	my $issue = XML::Element->new('issue');
	my $supplement = XML::Element->new('supplement');
	my $spage = XML::Element->new('startpage');
	my $year = XML::Element->new('year');


	$root->push_content($literal);
	$root->push_content($authors);
	$root->push_content($first_author);
	$root->push_content($title);
	$root->push_content($jtitle);
	$root->push_content($volume);
	$root->push_content($issue);
	$root->push_content($supplement);
	$root->push_content($spage);
	$root->push_content($year);

	$literal->push_content($cite->{'text'});
	$authors->push_content($cite->{'authors'});
	$first_author->push_content($cite->{'aufull'});
	$title->push_content($cite->{'atitle'});
	$jtitle->push_content($cite->{'jtitle'});
	$volume->push_content($cite->{'volume'});
	$issue->push_content($cite->{'issue'});
	$supplement->push_content($cite->{'supl'});
	$spage->push_content($cite->{'spage'});
	$year->push_content($cite->{'year'});

	print $xml_pi->as_XML;	
	print $root->as_XML;
	};


sub display_metadata {
        my $cite = shift;
        return if (!defined($cite->{'text'}));
 
        my $num = shift || 0;
 
        my $indent = ' ' x $num;
 
        print $indent, "<citation>\n";
        print $indent,"    <literal>$cite->{'text'}</literal>\n";
        print $indent,"    <authors>$cite->{'authors'}</authors>\n";
        print $indent,"    <first_author>$cite->{'aufull'}</first_author>\n";
        print $indent,"    <title>$cite->{'atitle'}</title>\n";
        print $indent,"    <journaltitle>$cite->{'jtitle'}</journaltitle>\n";
        print $indent,"    <volume>$cite->{'volume'}</volume>\n";
        print $indent,"    <issue>$cite->{'issue'}</issue>\n";
        print $indent,"    <supplement>$cite->{'supl'}</supplement>\n";
        print $indent,"    <startpage>$cite->{'spage'}</startpage>\n";
        print $indent,"    <year>$cite->{'year'}</year>\n";
        print $indent,"    <targetURL>$cite->{'targetURL'}</targetURL>\n"; 
        print $indent,"    <eprintID>$cite->{'eprintID'}</eprintID>\n";
        print $indent, "</citation>\n"; 
	};

	
1;   

__END__

=head1 NAME

Parser::Citation - Extract metadata from journal citation strings.

=head1 SYNOPSIS

 $cite = new Parser::Citation($str);

  
 $SourceString   = $cite->srcText(); 
 $Authors        = $cite->list_authours();
 $First_author   = $cite->first_author();
 $Article_title  = $cite->atitle();
 $Journal_title  = $cite->jtitle();
 $Volume         = $cite->volume();
 $Issue          = $cite->issue();
 $Supplement     = $cite->supplement();
 $Start_page     = $cite->startpage();
 $Year           = $cite->year();

 $cite->display_metadata();
 $cite->display_metadata_xml();

=head1 DESCRIPTION  

This module implements the Citation class. Objects of this class represent
citation strings, for eaxmple:

 G. Baym, C. Pethick, and D. Pines, Nature 224 (1969) 673.

It was written for processing journal citations, hence is not suitable
for extracting metadata from the citations to books, conference proceedings, 
technical reports, etc. 

=head1 CONSTRUCTOR

$cite = new Parser::Citation($str)

Note: the citation string should be a single line, containing no line breaks.

=head1 METHODS

The following methods are used to access individual metadata:

=over 4

=item $cite->srcText()

This method returns the original citation string.

=item $cite->list_authours()

This method returns a list of authors, separated by a colon.

=item $cite->first_author()

This methods returns the full name of the first author, in the
form of I<first name, initials, last name>.

=item $cite->atitle()

This methods returns the article title. Currently it only returns
titles quoted by double quotes in the original citation string.

=item $cite->jtitle()

This method returns the journal title. 

=item $cite->volume()

This method returns the volume number of the journal.

=item $cite->issue()

This method returns the issue number of the journal.

=item $cite->supplement()

This method returns the supplement number of the journal.

=item $cite->startpage()

This method returns the start page of an article.

=item $cite->year()

This method returns the year of publication.

=item $cite->display_metadata([<int>])

This methods displays all metadata extracted from the citation string, 
together with markup tags. The optional <int> parameter indecates
the amount of the indentation (i.e. leading spaces on each line).

=item $cite->display_metadata_xml()

This method displays all metadata extracted from the citation string, in XML
format.

=head1 EXAMPLE

$cite = new Parser::Citation('G. Baym, C. Pethick, and D. Pines, Nature 224 (1969) 673');

$cite->display_metadata();

will create:

 <citation>
     <literal>G. Baym, C. Pethick, and D. Pines, Nature 224 (1969) 673</literal>
     <authors>G.Baym:C.Pethick:D.Pines</authors>
     <first_author>G.Baym</first_author>
     <journaltitle>NATURE</journaltitle>
     <volume>224</volume>
     <startpage>673</startpage>
     <year>1969</year>
 </citation>   

=head1 AUTHOR

Zhuoan Jiao, zj@ecs.soton.ac.uk   

=cut
