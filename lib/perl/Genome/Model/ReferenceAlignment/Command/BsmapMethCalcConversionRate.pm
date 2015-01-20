package Genome::Model::ReferenceAlignment::Command::BsmapMethCalcConversionRate;

use strict;
use warnings;
use Genome;
use Genome::Model::Tools::Bsmap::MethCalcConversionRate;

class Genome::Model::ReferenceAlignment::Command::BsmapMethCalcConversionRate {
    is => 'Command::V2',
    has => [
        model => {
			is => 'Genome::Model::ReferenceAlignment',
            doc => 'Use genome model ID to calculate methylation conversion',
        },
        output_file => {
            is => 'String',
            is_optional => 1,
            doc => 'Output methylation conversion',
        },
    ],
};

sub execute {
    my $self = shift;
    my $output_file = $self->output_file;

	my $cfile;
	if ($output_file) {
		open($cfile, '>', $output_file) or die;
	} else {
		$cfile = \*STDOUT;
	}

	# get the bam paths of the last succeeded build
	my $dir = $self->model->last_succeeded_build->data_directory;
	# flagstat 
	my @flagstat = glob("$dir/alignments/*flagstat");
	my (@field, $total, $duplicates, $mapped, $properly);
	for my $flagstat (@flagstat) {
		if (-s "$flagstat"){
			print $cfile "\nMethylation alignment status:\n";
			print $cfile $flagstat, "\n";

			my $flagstat_data = Genome::Model::Tools::Sam::Flagstat->parse_file_into_hashref($flagstat);
			print $cfile "Total read\t=\t", $flagstat_data->{total_reads}, "\n";

			print $cfile "Duplicates\t=\t", $flagstat_data->{reads_marked_duplicates}, "\n";
			if ($flagstat_data->{total_reads} != 0) {
				my $dupe_rate = $flagstat_data->{reads_marked_duplicates} / $flagstat_data->{total_reads} * 100;
				print $cfile "Duplicates rate (%)\t=\t", $dupe_rate, "\n";
			}

			print $cfile "Mapped read\t=\t", $flagstat_data->{reads_mapped}, "\n";
			if ($flagstat_data->{total_reads} != 0) {
				print $cfile "Mapped rate (%)\t=\t", $flagstat_data->{reads_mapped_percentage}, "\n";
			}

			print $cfile "Properly paired\t=\t", $flagstat_data->{reads_mapped_in_proper_pairs}, "\n";
			if ($flagstat_data->{total_reads} != 0) {
				print $cfile "Properly paired rate (%)\t=\t", $flagstat_data->{reads_mapped_in_proper_pairs_percentage}, "\n";
			}
		}
		else {
			$self->error_message("can't find flagstat file");
		}
	}

	my %cases = (
		MT => { glob => "$dir/variants/snv/meth-ratio-*/MT/snvs.hq", name => "mtDNA" },
		lambda => { glob => "$dir/variants/snv/meth-ratio-*/gi_9626243_ref_NC_001416.1_/snvs.hq", name => "lambda" },
	);
	for my $chrom (keys %cases) {
		my ($glob, $name) = ($cases{$chrom}{glob}, $cases{$chrom}{name});

		my @file = glob($glob);
		for my $file (@file) {
			if (-s "$file"){
				Genome::Model::Tools::Bsmap::MethCalcConversionRate::bs_rate($file, $chrom, $cfile);
			}
			else {
				$self->error_message("can't find $name snvs file");
			}
		}
	}
	return 1;
}

