#!/usr/bin/perl
use Data::Dumper;
use strict;
use warnings;

sub largest {
  my (@digits) = @_;

  for( my $i=0; $i< scalar @digits; $i++ ) {
    next if $digits[$i] == 0 && $i==0;
    my $j = scalar @digits-1;
    my $largest_index = $i;
    while( $j >= $i ) {
      if( $digits[$j] > $digits[$largest_index] ) {
        unless( $i==0 && $digits[$j] ==0 ){
          $largest_index = $j;
        }
      }
      $j--;
    }

    if ( $largest_index != $i ) {
      my $buffer = $digits[$i];
      $digits[$i] = $digits[$largest_index];
      $digits[$largest_index] = $buffer;
      last;
    }
  }

  return join('',@digits);
}

sub smallest {
  my (@digits) = @_;
  
  for( my $i=0; $i< scalar @digits; $i++ ) {
    next if $digits[$i] == 0;
    my $j = scalar @digits-1;
    my $smallest_index = $i;
    while( $j >= $i ) {
      if( $digits[$j] < $digits[$smallest_index] ) {
        unless( $i==0 && $digits[$j] ==0 ){
          $smallest_index = $j;
        }
      }
      $j--;
    }

    if ( $smallest_index != $i ) {
      my $buffer = $digits[$i];
      $digits[$i] = $digits[$smallest_index];
      $digits[$smallest_index] = $buffer;
      last;
    }
  }
  return join('',@digits);
}

if( scalar @ARGV ) {
  foreach my $input ( @ARGV ) {
    my @digits = $input =~ m#(\d)#g;
    print "I: $input\nS: ". smallest(@digits)."\nL: ".largest(@digits)."\n\n";
  }
} else {
  my $input_path = "/home/francis/perl/numbers.txt";
  my $output_path = "/home/francis/perl/output.txt";
  open( my $input, '<', $input_path ) or die "Error: $!";
  open( my $output, '>', $output_path ) or die "Error: $!";
  my $i=0;
  while( my $row = <$input> ) {
    if ( $i<1 ){
      $i++;
      next;
    }
    chomp $row;
    my @digits = $row =~ m#(\d)#g;

    print $output "Case #$i: ".smallest(@digits)." ".largest(@digits)."\n";
    
    $i++;
  }
  close $input;
  close $output;
}
