#!/bin/bash
#rnaseqalign.sh

usage() {
  echo "-h Help documentation for hisat.sh"
  echo "-r  --Reference Genome: GRCh38 or GRCm38"
  echo "-x  --FastQ R1"
  echo "-y  --FastQ R2"
  echo "-a  --Method: hisat or star"
  echo "-p  --Prefix for output file name"
  echo "-u  [UMI sequences are in FQ Read Name]"
  echo "Example: bash rnaseqalign.sh -a hisat -p prefix -u -r /project/shared/bicf_workflow_ref/GRCh38 -x SRR1551047_1.fastq.gz  -y SRR1551047_2.fastq.gz"
  exit 1
}
OPTIND=1 # Reset OPTIND
while getopts :r:a:x:y:p:hu opt
do
    case $opt in
        r) index_path=$OPTARG;;
        x) fq1=$OPTARG;;
        y) fq2=$OPTARG;;
	a) algo=$OPTARG;;
	u) umi=1;;
        p) pair_id=$OPTARG;;
        h) usage;;
    esac
done

shift $(($OPTIND -1))

# Check for mandatory options
if [[ -z $pair_id ]] || [[ -z $fq1 ]]; then
    usage
fi

source /etc/profile.d/modules.sh
module load  samtools/gcc/1.6 picard/2.10.3
baseDir="`dirname \"$0\"`"
if [[ -z $SLURM_CPUS_ON_NODE ]]
then
    SLURM_CPUS_ON_NODE=1
fi
if [ $algo == 'star' ]
then
    if ($fq1 != $fq2)
    then
	module load star/2.4.2a
	STAR --genomeDir ${index_path}/star_index/ --readFilesIn $fq1 $fq2 --readFilesCommand zcat --genomeLoad NoSharedMemory --outFilterMismatchNmax 999 --outFilterMismatchNoverReadLmax 0.04 --outFilterMultimapNmax 20 --alignSJoverhangMin 8 --alignSJDBoverhangMin 1 --alignIntronMin 20 --alignIntronMax 1000000 --alignMatesGapMax 1000000 --outSAMheaderCommentFile COfile.txt --outSAMheaderHD @HD VN:1.4 SO:coordinate --outSAMunmapped Within --outFilterType BySJout --outSAMattributes NH HI AS NM MD --outSAMstrandField intronMotif --outSAMtype BAM SortedByCoordinate --quantMode TranscriptomeSAM --sjdbScore 1 --limitBAMsortRAM 60000000000 --outFileNamePrefix out
    else
	STAR --genomeDir ${index_path}/star_index/ --readFilesIn $fq1 --readFilesCommand zcat --genomeLoad NoSharedMemory --outFilterMismatchNmax 999 --outFilterMismatchNoverReadLmax 0.04 --outFilterMultimapNmax 20 --alignSJoverhangMin 8 --alignSJDBoverhangMin 1 --alignIntronMin 20 --alignIntronMax 1000000 --alignMatesGapMax 1000000 --outSAMheaderCommentFile COfile.txt --outSAMheaderHD @HD VN:1.4 SO:coordinate --outSAMunmapped Within --outFilterType BySJout --outSAMattributes NH HI AS NM MD --outSAMstrandField intronMotif --outSAMtype BAM SortedByCoordinate --quantMode TranscriptomeSAM --sjdbScore 1 --limitBAMsortRAM 60000000000 --outFileNamePrefix out
    fi
    mv outLog.final.out ${pair_id}.alignerout.txt
    mv outAligned.sortedByCoord.out.bam output.bam
else
    module load hisat2/2.1.0-intel
    if [ $fq1 == $fq2 ]
    then
	hisat2 -p $SLURM_CPUS_ON_NODE --rg-id ${pair_id} --rg LB:tx --rg PL:illumina --rg PU:barcode --rg SM:${pair_id} --add-chrname --no-unal --dta -x ${index_path}/hisat_index/genome -U $fq1 -S out.sam --summary-file ${pair_id}.alignerout.txt
    else
	hisat2 -p $SLURM_CPUS_ON_NODE --rg-id ${pair_id} --rg LB:tx --rg PL:illumina --rg PU:barcode --rg SM:${pair_id} --add-chrname --no-unal --dta -x ${index_path}/hisat_index/genome -1 $fq1 -2 $fq2 -S out.sam --summary-file ${pair_id}.alignerout.txt
    fi
    samtools view -1 --threads $SLURM_CPUS_ON_NODE -o output.bam out.sam
fi
if [[ $umi==1 ]]
then
    python ${baseDir}/add_umi_bam.py -b output.bam -o output.unsort2.bam
    mv output.unsort2.bam output.bam
fi
samtools sort -@ $SLURM_CPUS_ON_NODE -O BAM -n -o  output.nsort.bam output.bam
java -jar $PICARD/picard.jar FixMateInformation ASSUME_SORTED=TRUE SORT_ORDER=coordinate ADD_MATE_CIGAR=TRUE I=output.nsort.bam O=${pair_id}.bam
samtools index -@ $SLURM_CPUS_ON_NODE ${pair_id}.bam
