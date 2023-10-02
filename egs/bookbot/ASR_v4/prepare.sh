#!/usr/bin/env bash

# fix segmentation fault reported in https://github.com/k2-fsa/icefall/issues/674
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

set -eou pipefail

nj=10
stage=-1
stop_stage=100

# Split L subset to this number of pieces
# This is to avoid OOM during feature extraction.
num_splits=2000

dl_dir=$PWD/download
splits_dir=$PWD/splits_dir

. shared/parse_options.sh || exit 1

# All files generated by this script are saved in "data".
# You can safely remove "data" and rerun this script to regenerate it.
mkdir -p data

log() {
  # This function is from espnet
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

log "dl_dir: $dl_dir"


if [ $stage -le 0 ] && [ $stop_stage -ge 0 ]; then
  log "Stage 0: Download data"

  if [ ! -d $dl_dir/timit ]; then
    lhotse download bookbot-huggingface bookbot/timit $dl_dir phonemes_ipa " "
  fi

  if [ ! -d $dl_dir/libriphone ]; then
    lhotse download bookbot-huggingface bookbot/libriphone $dl_dir phonemes_ipa " "
  fi

  if [ ! -d $dl_dir/common_voice_13_0_en_zipformer ]; then
    lhotse download bookbot-huggingface bookbot/common_voice_13_0_en_zipformer $dl_dir phonemes_ipa " "
  fi

  if [ ! -d $dl_dir/gigaspeech_zipformer ]; then
    lhotse download bookbot-huggingface bookbot/gigaspeech_zipformer $dl_dir phonemes_ipa " "
  fi

  if [ ! -d $dl_dir/bookbot_en_phonemes ]; then
    lhotse download bookbot-huggingface bookbot/bookbot_en_phonemes $dl_dir phonemes_ipa " "
  fi

  if [ ! -d $dl_dir/austalk_words_mq ]; then
    lhotse download bookbot-huggingface bookbot/austalk_words_mq $dl_dir phonemes_ipa " "
  fi

  if [ ! -d $dl_dir/sc_cw_children ]; then
    lhotse download bookbot-huggingface bookbot/sc_cw_children $dl_dir phonemes_ipa " "
  fi

  if [ ! -d $dl_dir/l2-arctic ]; then
    lhotse download bookbot-huggingface bookbot/l2-arctic $dl_dir phonemes_ipa " "
  fi

  if [ ! -d $dl_dir/speechocean762 ]; then
    lhotse download bookbot-huggingface bookbot/speechocean762 $dl_dir phonemes_ipa " "
  fi

  if [ ! -d $dl_dir/musan ]; then
    lhotse download musan $dl_dir
  fi

  if [ ! -d $dl_dir/audio_splits ]; then
    lhotse download hallway $dl_dir
  fi
fi

if [ $stage -le 1 ] && [ $stop_stage -ge 1 ]; then
  log "Stage 1: Prepare manifests"
  mkdir -p data/manifests

  lhotse prepare bookbot-huggingface $dl_dir/timit data/manifests
  lhotse prepare bookbot-huggingface $dl_dir/libriphone data/manifests
  lhotse prepare bookbot-huggingface $dl_dir/common_voice_13_0_en_zipformer data/manifests
  lhotse prepare bookbot-huggingface $dl_dir/gigaspeech_zipformer data/manifests
  lhotse prepare bookbot-huggingface $dl_dir/bookbot_en_phonemes data/manifests
  lhotse prepare bookbot-huggingface $dl_dir/austalk_words_mq data/manifests
  lhotse prepare bookbot-huggingface $dl_dir/sc_cw_children data/manifests
  lhotse prepare bookbot-huggingface $dl_dir/l2-arctic data/manifests
  lhotse prepare bookbot-huggingface $dl_dir/speechocean762 data/manifests
  lhotse prepare musan $dl_dir/musan data/manifests
  lhotse prepare hallway $dl_dir/audio_splits data/manifests
fi

if [ $stage -le 2 ] && [ $stop_stage -ge 2 ]; then
  log "Stage 2: Compute fbanks"
  mkdir -p data/fbank

  ./local/compute_fbank_timit.py
  ./local/compute_fbank_libriphone.py
  ./local/compute_fbank_bookbot.py
  ./local/compute_fbank_austalk.py
  ./local/compute_fbank_sccw.py
  ./local/compute_fbank_l2.py
  ./local/compute_fbank_speechocean.py
  ./local/compute_fbank_musan.py
  ./local/compute_fbank_hallway.py
fi

if [ $stage -le 3 ] && [ $stop_stage -ge 3 ]; then
  log "Stage 3: Preprocess GigaSpeech manifest"
  if [ ! -f data/fbank/.gigaspeech_preprocess.done ]; then
    ./local/preprocess_gigaspeech.py
    touch data/fbank/.gigaspeech_preprocess.done
  fi
fi

if [ $stage -le 4 ] && [ $stop_stage -ge 4 ]; then
  log "Stage 4: Split L subset into ${num_splits} pieces"
  split_dir=data/fbank/gigaspeech_L_split_${num_splits}
  if [ ! -f $split_dir/.gigaspeech_L_split.done ]; then
    lhotse split $num_splits ./data/fbank/gigaspeech_zipformer_cuts_L_raw.jsonl.gz $split_dir
    touch $split_dir/.gigaspeech_L_split.done
  fi
fi

if [ $stage -le 5 ] && [ $stop_stage -ge 5 ]; then
  log "Stage 5: Compute features for L"
  # Note: The script supports --start and --stop options.
  # You can use several machines to compute the features in parallel.
  if [ ! -f data/fbank/.gigaspeech_L.done ]; then
    ./local/compute_fbank_gigaspeech_splits.py \
      --num-workers $nj \
      --batch-duration 600 \
      --num-splits $num_splits
    touch data/fbank/.gigaspeech_L.done
  fi
fi

if [ $stage -le 6 ] && [ $stop_stage -ge 6 ]; then
  log "Stage 6: Combine features for L (may take 15 hours)"
  if [ ! -f data/fbank/gigaspeech_cuts_L.jsonl.gz ]; then
    pieces=$(find data/fbank/gigaspeech_L_split_${num_splits} -name "gigaspeech_zipformer_cuts_L.*.jsonl.gz")
    lhotse combine $pieces data/fbank/gigaspeech_zipformer_cuts_L.jsonl.gz
  fi
fi

if [ $stage -le 7 ] && [ $stop_stage -ge 7 ]; then
  log "Stage 7: Prepare phone based lang"
  lang_dir=data/lang_phone
  mkdir -p $lang_dir

  ./local/prepare_lexicon.py \
   --manifests-dir data/manifests \
   --lang-dir $lang_dir

  if [ ! -f $lang_dir/L_disambig.pt ]; then
    ./local/prepare_lang.py --lang-dir $lang_dir
  fi
fi