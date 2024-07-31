#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
WORK_DIR="${SCRIPT_DIR}/DeepVariant_demo"
mkdir -p ${WORK_DIR}
cd ${WORK_DIR}


INPUT_DIR="${WORK_DIR}/input"
OUTPUT_DIR="${WORK_DIR}/output"
BENCHMARK_DIR="${WORK_DIR}/benchmark"
MODELS_DIR="${WORK_DIR}/models"
LOGS_DIR="${WORK_DIR}/logs"
mkdir -p ${OUTPUT_DIR}
mkdir -p ${BENCHMARK_DIR}
mkdir -p ${LOGS_DIR}


######################################
# tool cloning and building
######################################
if [ ! -d "${WORK_DIR}/deepvariant" ]; then
  git clone https://github.com/google/deepvariant
fi

docker build -t deepvariant:latest -f ${WORK_DIR}/deepvariant/Dockerfile ${WORK_DIR}/deepvariant


######################################
# input data downloading and preparing
######################################
CONTIGS="chr20"
START_POS=100000
END_POS=300000

if [ ! -d ${INPUT_DIR} ]; then
    # download quick demo data
    mkdir -p ${INPUT_DIR}

    # GRCh38_no_alt Reference
    wget -P ${INPUT_DIR} http://www.bio8.cs.hku.hk/clair3/demo/quick_demo/illumina/GRCh38_chr20.fa
    wget -P ${INPUT_DIR} http://www.bio8.cs.hku.hk/clair3/demo/quick_demo/illumina/GRCh38_chr20.fa.fai

    # BAM chr20:100000-300000
    wget -P ${INPUT_DIR} http://www.bio8.cs.hku.hk/clair3/demo/quick_demo/illumina/HG003_chr20_demo.bam
    wget -P ${INPUT_DIR} http://www.bio8.cs.hku.hk/clair3/demo/quick_demo/illumina/HG003_chr20_demo.bam.bai

    # GIAB Truth VCF and BED
    wget -P ${INPUT_DIR} http://www.bio8.cs.hku.hk/clair3/demo/quick_demo/illumina/HG003_GRCh38_chr20_v4.2.1_benchmark.vcf.gz
    wget -P ${INPUT_DIR} http://www.bio8.cs.hku.hk/clair3/demo/quick_demo/illumina/HG003_GRCh38_chr20_v4.2.1_benchmark.vcf.gz.tbi
    wget -P ${INPUT_DIR} http://www.bio8.cs.hku.hk/clair3/demo/quick_demo/illumina/HG003_GRCh38_chr20_v4.2.1_benchmark_noinconsistent.bed

    # extract specific region
    echo -e "${CONTIGS}\t${START_POS}\t${END_POS}" > ${INPUT_DIR}/quick_demo.bed
fi


######################################
# tool running
######################################
THREADS=4
REF="${INPUT_DIR}/GRCh38_chr20.fa"
BAM="${INPUT_DIR}/HG003_chr20_demo.bam"
BED="${INPUT_DIR}/quick_demo.bed"


docker run \
    --volume ${INPUT_DIR}:${INPUT_DIR}:ro \
    --volume ${OUTPUT_DIR}:${OUTPUT_DIR} \
    deepvariant:latest \
        /opt/deepvariant/bin/run_deepvariant \
            --model_type=WGS \
            --ref=${REF} \
            --reads=${BAM} \
            --regions=${BED}  \
            --output_vcf=${OUTPUT_DIR}/output.vcf.gz \
            --intermediate_results_dir=${OUTPUT_DIR}/tmp \
            --num_shards=${THREADS} | tee ${LOGS_DIR}/deepvariant.log


######################################
# benchmarking
######################################
if [ ! -d "${WORK_DIR}/hap.py" ]; then
  git clone https://github.com/Illumina/hap.py
fi

docker build -t hap.py:latest -f ${WORK_DIR}/hap.py/Dockerfile ${WORK_DIR}/hap.py

BASELINE_VCF="${INPUT_DIR}/HG003_GRCh38_chr20_v4.2.1_benchmark.vcf.gz"
BASELINE_BED="${INPUT_DIR}/HG003_GRCh38_chr20_v4.2.1_benchmark_noinconsistent.bed"
OUTPUT_VCF="${OUTPUT_DIR}/output.vcf.gz"
REF="${INPUT_DIR}/GRCh38_chr20.fa"
THREADS=4
docker run -it  \
    --volume ${INPUT_DIR}:${INPUT_DIR}:ro \
    --volume ${OUTPUT_DIR}:${OUTPUT_DIR}:ro \
    --volume ${BENCHMARK_DIR}:${BENCHMARK_DIR} \
    hap.py:latest \
        /opt/hap.py/bin/hap.py \
            ${BASELINE_VCF} \
            ${OUTPUT_VCF} \
            -f ${BASELINE_BED} \
            -r ${REF} \
            -o "${BENCHMARK_DIR}/happy" \
            -l ${CONTIGS}:${START_POS}-${END_POS} \
            --engine=vcfeval \
            --threads=${THREADS} \
            --pass-only | tee ${LOGS_DIR}/hap.py.log

cat "${BENCHMARK_DIR}/happy.summary.csv"