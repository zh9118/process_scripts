#!/usr/bin/perl -w
#svvcf2bed.pl

use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);

my %opt = ();
my $results = GetOptions (\%opt,'fusion|f=s','prefix|p=s','help|h');

my %entrez;
open ENT, "</project/shared/bicf_workflow_ref/gene_info.human.txt" or die $!;
my $headline = <ENT>;
while (my $line = <ENT>) {
  chomp($line);
  my @row = split(/\t/,$line);{
      $entrez{$row[2]} = $row[1];
  }
}
open OM, "</project/shared/bicf_workflow_ref/GRCh38/utswv2_known_genefusions.txt" or die $!;
while (my $line = <OM>) {
    chomp($line);
    $known{$line} = 1;
}
close OM;
open OM, "</project/shared/bicf_workflow_ref/GRCh38/panel1385.genelist.txt" or die $!;
while (my $line = <OM>) {
    chomp($line);
    $keep{$line} = 1;
}

open OUT, ">$opt{prefix}\.translocations.txt" or die $!;
open OUTIR, ">$opt{prefix}\.cbioportal.genefusions.txt" or die $!;

print OUT join("\t","FusionName","LeftGene","RightGene","LefttBreakpoint",
	       "RightBreakpoint","LeftStrand","RightStrand","RNAReads",
	       "DNAReads"),"\n";
print OUTIR join("\t","Hugo_Symbol","Entrez_Gene_Id","Center","Tumor_Sample_Barcode",
               "Fusion","DNA_support","RNA_support","Method","Frame"),"\n";

my $sname = (split(/_DNA_panel1385/,$opt{prefix}))[0];

open FUSION, "<$opt{fusion}" or die $!;
my $header = <FUSION>;
chomp($header);
$header =~ s/^#//;
my @hline = split(/\t/,$header);
while (my $line = <FUSION>) {
  chomp($line);
  my @row = split(/\t/,$line);
  my %hash;
  foreach my $i (0..$#row) {
    $hash{$hline[$i]} = $row[$i];
  }
  my ($left_chr,$left_pos,$left_strand) = split(/:/,$hash{LeftBreakpoint});
  my ($right_chr,$right_pos,$right_strand) = split(/:/,$hash{RightBreakpoint});
  $hash{LeftBreakpoint} = join(":",$left_chr,$left_pos);
  $hash{RightBreakpoint} = join(":",$right_chr,$right_pos);
  $hash{LeftStrand} = $left_strand;
  $hash{RightStrand} = $right_strand;
  $hash{LeftGene} = (split(/\^/,$hash{LeftGene}))[0];
  $hash{RightGene} = (split(/\^/,$hash{RightGene}))[0];
  next unless ($keep{$hash{LeftGene}} || $keep{$hash{RightGene}});
  $hash{SumRNAReads} += $hash{JunctionReadCount}+$hash{SpanningFragCount};
  my $fname = join("--",$hash{LeftGene},$hash{RightGene});
  my $fname2 = join("--",sort {$a cmp $b} $hash{LeftGene},$hash{RightGene});
  my $ename = join("--",$entrez{$hash{LeftGene}},$entrez{$hash{RightGene}});
  my ($dna_support,$rna_support)=("no","no");
  if ($known{$fname2} && ($hash{SumRNAReads} >= 3)|| ($hash{SumRNAReads} >= 5)) {
    $rna_support = "yes";
    print OUT join("\t",$fname,$hash{LeftGene},$hash{RightGene},
		   $hash{LeftBreakpoint},$hash{RightBreakpoint},$hash{LeftStrand},
		   $hash{RightStrand},$hash{SumRNAReads},0),"\n";
    print OUTIR join("\t",$fname,$ename,"UTSW NGS Clinical Sequencing Lab",$sname,$fname." fusion",
		     0,$rna_support,"STAR 2.5.2b","N/A"),"\n";
  }
}

close OUT;
close OUTIR;
