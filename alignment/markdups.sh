#!/bin/bash
#hisat.sh

usage() {
  echo "-h  --Help documentation for markdups.sh"
  echo "-m  --Mark Duplication Method: sambamba, samtools, picard, picard_umi, fgbio_umi, null; default is null"
  echo "-b  --BAM file"
  echo "-p  --Prefix for output file name"
  echo "Example: bash markdups.sh -p prefix -b file.bam -a picard"
  exit 1
}
OPTIND=1 # Reset OPTIND
while getopts :a:b:p:h opt
do
    case $opt in
        a) algo=$OPTARG;;
        b) sbam=$OPTARG;;
        p) pair_id=$OPTARG;;
        h) usage;;
    esac
done

shift $(($OPTIND -1))

# Check for mandatory options
if [[ -z $pair_id ]] || [[ -z $sbam ]]; then
    usage
fi

if [[ -z $SLURM_CPUS_ON_NODE ]]
then
    SLURM_CPUS_ON_NODE=1
fi

module load picard/2.10.3 samtools/1.6

if [ $algo == 'sambamba' ]
then
    module load speedseq/20160506
    sambamba markdup -t $SLURM_CPUS_ON_NODE -r ${sbam} ${pair_id}.dedup.bam
elif [ $algo == 'samtools' ]
then
    module load samtools/1.6
    samtools sort -n -@ $SLURM_CPUS_ON_NODE -o nsort.bam ${sbam}
    samtools fixmate -c --output-fmt BAM -m -@ $SLURM_CPUS_ON_NODE nsort.bam fix.bam
    samtools sort -n -@ $SLURM_CPUS_ON_NODE -o sort.bam fix.bam
    samtools markdup -s --output-fmt BAM -@ $SLURM_CPUS_ON_NODE sort.bam ${pair_id}.dedup.bam
elif [ $algo == 'picard' ]
then
    java -Djava.io.tmpdir=./ -Xmx4g  -jar $PICARD/picard.jar MarkDuplicates I=${sbam} O=${prefix}.dedup.bam M=${pair_id}.dedup.stat.txt
elif [ $algo == 'picard_umi' ]
then
    java -Djava.io.tmpdir=./ -Xmx4g  -jar $PICARD/picard.jar MarkDuplicates BARCODE_TAG=RX I=${sbam} O=${pair_id}.dedup.bam M=${pair_id}.dedup.stat.txt
elif [ $algo == 'fgbio_umi' ]   
then
    source activate fgbiotools
    fgbio GroupReadsByUmi -s identity -i ${sbam} -o ${pair_id}.group.bam -m 10
    fgbio CallMolecularConsensusReads -i ${pair_id}.group.bam -p consensus -M 1 -o ${pair_id}.consensus.bam -S ':none:'
    source deactivate
    module load bwa/intel/0.7.15
    samtools index ${pair_id}.consensus.bam
    samtools fastq -1 ${pair_id}.consensus.R1.fastq -2 ${pair_id}.consensus.R2.fastq ${pair_id}.consensus.bam
    gzip ${pair_id}.consensus.R1.fastq
    gzip ${pair_id}.consensus.R2.fastq
    bwa mem -M -C -t 2 -R '@RG\tID:${pair_id}\tLB:tx\tPL:illumina\tPU:barcode\tSM:${pair_id}' /project/shared/bicf_workflow_ref/GRCh38/genome.fa ${pair_id}.consensus.R1.fastq.gz ${pair_id}.consensus.R2.fastq.gz | samtools view -1 - > ${pair_id}.consensus.bam
    samtools sort --threads 10 -o ${pair_id}.dedup.bam ${pair_id}.consensus.bam
else
    cp ${sbam} ${prefix}.dedup.bam    
fi