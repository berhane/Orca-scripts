#!/bin/bash
# ------------------------------------------------------------------
# runorca.sh
#          Sets up and runs an Orca calculaion
# ------------------------------------------------------------------
# Change log 
#  0.1.0 - 04/18/19 - started adapting script to follow to certain standards 
#  0.1.2  - 05/04/19 - option to enable/disable coping back *gbw, *opt, *trj
#  0.1.3  - 10/29/19 - print some things to stderr  
#  0.1.4  - 12/05/19 - added ORCA version selection option 
#  0.1.5  - 02/20/20 - added MD results readback
# 
SCRIPT=$0
VERSION=0.1.5
LASTMODIFIED=02_20_20

USAGE="
USAGE: $SCRIPT [-v] [-s] -i <input-file-name>\n
   where\n
   input-file-name - is the input file name\n
   -v - is an optional flag to use select a specfic version of Orca.\n
   -s - is an optional flag to use save all files including *gbw *opt *trj\n
   EG.  : $SCRIPT -i test.inp \n
        : $SCRIPT -s -i test.inp \n
        : $SCRIPT -v 4.1.2 -s -i test.inp \n\n
   runs Orca using test.inp, with the default node-local scratch, or cluster-wide scratch space"

# -----------------------------------------------------------------
#  Option PARSING And PROCESSING 
# -----------------------------------------------------------------
if [ $# == 0 ] ; then
    echo -e $USAGE
    exit 1;
fi

while getopts "v:hsi:" lopt
   do
   case "$lopt" in
      v ) ORCA_VERSION=$OPTARG ;;
      h ) echo -e $USAGE; exit 0 ;;
      i ) INPUT_FILE=$OPTARG 
            [[ ! -f $INPUT_FILE ]] && { 
               echo "$INPUT_FILE doesn't exist" 
               exit 1 
               } ;;
      s ) export SAVE=1 ;;
      \? ) echo "Unknown option $OPTARG"; exit 0;;
      :  ) echo "No argument value for option $OPTARG"; exit 0;;
       * ) echo "Unknown error while processing options"; exit 0;;
    esac
  done

shift $(($OPTIND - 1))

# set up some variables based on the computing environment
if [[ -n "${PBS_O_HOST}" ]]; then
   MASTER_NODE=$PBS_O_HOST
   WORK=$PBS_O_WORKDIR
   JOB_ID=$PBS_JOBID
elif [[ -n "${SLURM_SUBMIT_HOST}" ]]; then
   MASTER_NODE=$SLURM_SUBMIT_HOST
   WORK=$SLURM_SUBMIT_DIR
   JOB_ID=$SLURM_JOB_ID
else
   MASTER_NODE=`hostname`
   WORK=`pwd`
   JOB_ID=`date -u +"%Y-%m-%d-T%H-%M-%S"`
   sleep 1
fi


# -----------------------------------------------------------------
#  Option PARSING And PROCESSING 
# -----------------------------------------------------------------
#--- BEGIN - Edit these based on your local computing environment --- 
# define location of scratch directory, ORCA and OpenMPI 
MYSCRATCH=/scratch/$USER/$JOB_ID
orca_path=/opt/ohpc/pub/apps/chem/orca/4.2.1
openmpi_path=/opt/ohpc/pub/mpi/openmpi3-gnu8/3.1.3
#--- END 

# add Orca and OpenMPI to your path
if [[ ! -x "${orca_path}/orca" ]]; then
  echo "ORCA not found." >&2
  return 1
fi
if [[ ! -d "${openmpi_path}/lib" ]]; then
  echo "OpenMPI installation not found." >&2
  return 2
fi

if [[ ! ${PATH} =~ ${orca_path} ]]; then
  export PATH="${orca_path}/bin":$PATH
fi
if [[ ! ${PATH} =~ ${openmpi_path} ]]; then
  export PATH="${openmpi_path}/bin":$PATH
fi
if [[ ! ${LD_LIBRARY_PATH} =~ ${orca_path} ]]; then  
  export LD_LIBRARY_PATH=${LD_LIBRARY_PATH+"${LD_LIBRARY_PATH}:"}${orca_path}
fi
if [[ ! ${LD_LIBRARY_PATH} =~ "${openmpi_path}/lib" ]]; then  
  export LD_LIBRARY_PATH=${LD_LIBRARY_PATH+"${LD_LIBRARY_PATH}:"}"${openmpi_path}/lib"
fi

# -----------------------------------------------------------------
#  Start Running Orca
# -----------------------------------------------------------------
echo "Running as $SCRIPT -i $INPUT_FILE using $MYSCRATCH as temporary scratch space" 

umask 0022
SUFFIX=`echo $INPUT_FILE | awk -F"." '{print "."$NF}'`
BASE=`basename $INPUT_FILE $SUFFIX`
echo "BASE = $BASE"
export WORK=`pwd`
echo "WORK = $WORK"
echo "SCRATCH = $MYSCRATCH"

echo "Running the $ORCA from directory $WORK on " `hostname`
echo "Job started on " `date`

echo "*************************************************************************" > $BASE.out
echo "Running ORCA " `which orca` >> $BASE.out
echo "with MPI" `which mpirun` >> $BASE.out
echo "from submission directory " `pwd` >> $BASE.out
echo "using scratch space at $MYSCRATCH" >> $BASE.out
echo "on" `hostname`" on "`date`"." >> $BASE.out
echo "*************************************************************************" >> $BASE.out

alias cp='cp -f'

if [ ! -d "$MYSCRATCH" ]; then
   mkdir -p $MYSCRATCH
fi

cp $BASE$SUFFIX $MYSCRATCH/
MYXYZ=`grep -m 1 "xyzfile" $BASE$SUFFIX | awk '{print $NF}'`

[[ -e "$MYXYZ" ]] && { cp -f $MYXYZ $MYSCRATCH/ ; }
[[ -e "*.hess" ]] && { cp -f *.hess $MYSCRATCH/ ; }
[[ -e "*.opt" ]] && { cp -f *.opt $MYSCRATCH/ ; }
[[ -e "*.gbw" ]] && { cp -f *.gbw $MYSCRATCH/ ; }
[[ -e "*.mdrestart" ]] && { cp -f *.mdrestart $MYSCRATCH/ ; }
[[ -e "*.csv" ]] && { cp -f *.csv $MYSCRATCH/ ; }

# copy other XYZ files specified in the input file
for file in `grep ".xyz" $BASE$SUFFIX |sed "s/\"//g"| awk '{print $NF}'`; do echo "$file copied to scratch directory" ; cp $file $MYSCRATCH/; done

cd $MYSCRATCH
ls

# start running Orca
$orca_path/orca $BASE$SUFFIX >> $WORK/$BASE.out
echo "*************************************************************************" >> $WORK/$BASE.out
echo "ORCA finished on "`hostname`" on "`date`"." >> $WORK/$BASE.out
echo "*************************************************************************" >> $WORK/$BASE.out
echo "" >> $WORK/$BASE.out

# Copy data back to initial directory
if [ "$SAVE" ]; then
   for FILE in `ls | grep -e gbw -e xyz -e opt -e trj -e hess | grep -v "proc[0-9]"`
     do
      cp -f $FILE $WORK/ 
     done
else
   for FILE in `ls | grep -e xyz | grep -v "proc[0-9]" | grep -v "trj"`
     do
       cp -f $FILE $WORK/ 
     done
fi

# 
ls
cd $WORK
rm -rf $MYSCRATCH

echo "Job ended on " `date`
