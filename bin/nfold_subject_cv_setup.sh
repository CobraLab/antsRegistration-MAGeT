#!/bin/bash
# Generator for cross validation of MaGeT, shamelessly stolen from ealier script
# Start by running a mb run with all inputs as atlases, templates and subjects, skip voting
# This primes the pipeline with all the possible registrations
# Then, run nfold_cv_setup.sh <nfolds> <natlases> <ntemplates>
# This shuffles the list of inputs and creates <nfolds> random samples satisftying
# <natlases> and <ntemplates> for every single subject
# Afterwards links into the directory the already processed transforms and candidate labels
# Then all that is left is to run mb.sh in each directory to complete the voting stage

nfolds=$1
natlases=$2
ntemplates=$3
origpool=(input/atlas/*t1.mnc)

if [[ $4 ]]
then
    targetdir=$4
else
    targetdir=.
fi

i=0
for subject in "${origpool[@]}"
do
echo $subject

subjectname=$(basename $subject)
if [[ -d $targetdir/NFOLDCV/${natlases}atlases_${ntemplates}templates_fold/$subjectname ]]
then
    ((i++))
    continue
fi

pool=( "${origpool[@]::$i}" "${origpool[@]:$((i+1))}" )

  for fold in $(seq $nfolds)
  do
      #Shuffle inputs in a random list using sort
      pool=($(printf "%s\n" "${pool[@]}" | sort -R))
      #Since list is now random, slice array according to numbers provided before
      atlases=("${pool[@]:0:$natlases}")
      #subjects=("${pool[@]:$natlases}")
      templates=("${pool[@]:$natlases:$ntemplates}")

      #Setup folders for random run
      folddir=$targetdir/NFOLDCV/${natlases}atlases_${ntemplates}templates_fold${fold}/${subjectname}
      mkdir -p $folddir/input/{atlas,template,subject}
      mkdir -p $folddir/output/labels/majorityvote

      #Link in precomputed transforms and candidate labels
      ln -s $(readlink -f output/transforms) $folddir/output/transforms
      ln -s $(readlink -f output/labels/candidates) $folddir/output/labels/candidates

      #Do a trick of replacing _t1.mnc with * to allow bash expansion to include all label files
      tmp=("${atlases[@]/_t1.mnc/*}")
      ln -s ${tmp[@]} $folddir/input/atlas
      ln -s "${templates[@]}" $folddir/input/template
      ln -s $subject $folddir/input/subject
      (cd $folddir; mb.sh)
  done
((i++))

done
nfold_subject_cv_collect.sh ${natlases}atlases_${ntemplates}templates.csv ${natlases}atlases_${ntemplates}templates $targetdir && rm -r $targetdir/NFOLDCV/${natlases}atlases_${ntemplates}templates_fold*
