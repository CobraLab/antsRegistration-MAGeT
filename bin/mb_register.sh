#!/bin/bash
if [[ -n ${__mb_debug:-} ]]; then
  set -x
fi
set -euo pipefail
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${THREADS_PER_COMMAND:-$(nproc)}
export ITK_USE_THREADPOOL=1
export ITK_GLOBAL_DEFAULT_THREADER=Pool

tmpdir=$(mktemp -d)

movingfile1=$1
fixedfile1=$2
outputdir=$3
shift 3
labelfiles=( "$@" )

movingmask="NOMASK"
fixedmask="NOMASK"

ext=$(basename ${movingfile1} | grep -o -E '(.mnc|.nii|.nii.gz|.nrrd|.hdr)')
fixed_minimum_resolution=$(python -c "print(min([abs(x) for x in [float(x) for x in \"$(PrintHeader ${fixedfile1} 1)\".split(\"x\")]]))")
moving_minimum_resolution=$(python -c "print(min([abs(x) for x in [float(x) for x in \"$(PrintHeader ${movingfile1} 1)\".split(\"x\")]]))")
fixed_maximum_resolution=$(python -c "print(max([ a*b for a,b in zip([abs(x) for x in [float(x) for x in \"$(PrintHeader ${fixedfile1} 1)\".split(\"x\")]],[abs(x) for x in [float(x) for x in \"$(PrintHeader ${fixedfile1} 2)\".split(\"x\")]])]))")

if [[ -n ${__mb_fast:-} ]]; then
  __mb_float="--float 1"
  __mb_syn_metric="--metric Mattes[${fixedfile1},${movingfile1},1,32,None]"
else
  __mb_syn_metric="--metric CC[${fixedfile1},${movingfile1},1,4,None]"
  __mb_float="--float 0"
fi

if ((${#labelfiles[@]} > 0)); then
  #Flatten all the label files into a mask
  cp ${labelfiles[0]} ${tmpdir}/mergedmask${ext}
  if ((${#labelfiles[@]} > 1)); then
    for label in "${labelfiles[@]}"; do
      ImageMath 3 ${tmpdir}/mergedmask${ext} addtozero ${tmpdir}/mergedmask${ext} ${label}
    done
  fi
  #Binarize the labels
  ThresholdImage 3 ${tmpdir}/mergedmask${ext} ${tmpdir}/mergedmask${ext} 0.5 inf 1 0
  #Morphologically pad the labelmask 3mm radius
  iMath 3 ${tmpdir}/movinglabelmask${ext} MD ${tmpdir}/mergedmask${ext} $(python -c "print(3.0/${moving_minimum_resolution})") 1 ball 1
  movingmask=${tmpdir}/movinglabelmask${ext}
fi

if [[ ! -s ${outputdir}/$(basename ${movingfile1})-$(basename ${fixedfile1})0_GenericAffine.xfm ]]
then
  antsRegistration --dimensionality 3 ${__mb_float} ${MB_VERBOSE:-} --minc \
    --output [${outputdir}/$(basename ${movingfile1})-$(basename ${fixedfile1})] \
    --initial-moving-transform [${fixedfile1},${movingfile1},1] \
    $(eval echo $(ants_generate_iterations.py --min ${fixed_minimum_resolution} --max ${fixed_maximum_resolution} --output multilevel-halving --convergence 1e-7))
fi

if [[ (! -s ${outputdir}/$(basename ${movingfile1})_labelmask${ext} ) && ( ${movingmask} != "NOMASK" ) ]]; then
  antsApplyTransforms -d 3 ${__mb_float} -i ${movingmask} -o ${outputdir}/$(basename ${movingfile1})_labelmask${ext} \
    -t ${outputdir}/$(basename ${movingfile1})-$(basename ${fixedfile1})0_GenericAffine.xfm -r ${fixedfile1} \
    -n GenericLabel
  fixedmask=${outputdir}/$(basename ${movingfile1})_labelmask${ext}
fi

nonlinear_steps=$(ants_generate_iterations.py --min ${fixed_minimum_resolution} --max ${fixed_maximum_resolution})
antsRegistration --dimensionality 3 ${__mb_float} ${MB_VERBOSE:-} --minc \
  --output [${outputdir}/$(basename ${movingfile1})-$(basename ${fixedfile1})] \
  --initial-moving-transform ${outputdir}/$(basename ${movingfile1})-$(basename ${fixedfile1})0_GenericAffine.xfm \
  --transform "SyN[0.25,3,0]" \
  ${__mb_syn_metric} \
  $(eval echo ${nonlinear_steps}) \
  --masks [${fixedmask},${movingmask}]

rm -rf ${tmpdir}
