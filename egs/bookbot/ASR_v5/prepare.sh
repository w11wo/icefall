#!/usr/bin/env bash

# fix segmentation fault reported in https://github.com/k2-fsa/icefall/issues/674
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

set -eou pipefail

stage=-1
stop_stage=100

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

  # if [ ! -d $dl_dir/timit ]; then
  #   lhotse download bookbot-huggingface bookbot/timit $dl_dir
  # fi

  if [ ! -d $dl_dir/libriphone ]; then
    lhotse download bookbot-huggingface bookbot/libriphone $dl_dir text ""
  fi

  # if [ ! -d $dl_dir/common-voice-13_0-en-v1 ]; then
  #   lhotse download bookbot-huggingface bookbot/common-voice-13_0-en-v1 $dl_dir
  # fi

  # if [ ! -d $dl_dir/bookbot_en_phonemes ]; then
  #   lhotse download bookbot-huggingface bookbot/bookbot_en_phonemes $dl_dir
  # fi

  # if [ ! -d $dl_dir/austalk_words_mq ]; then
  #   lhotse download bookbot-huggingface bookbot/austalk_words_mq $dl_dir
  # fi

  # if [ ! -d $dl_dir/sc_cw_children ]; then
  #   lhotse download bookbot-huggingface bookbot/sc_cw_children $dl_dir
  # fi

  # if [ ! -d $dl_dir/l2-arctic ]; then
  #   lhotse download bookbot-huggingface bookbot/l2-arctic $dl_dir
  # fi

  # if [ ! -d $dl_dir/speechocean762 ]; then
  #   lhotse download bookbot-huggingface bookbot/speechocean762 $dl_dir
  # fi

  if [ ! -d $dl_dir/musan ]; then
    lhotse download musan $dl_dir
  fi

  # if [ ! -d $dl_dir/audio_splits ]; then
  #   lhotse download hallway $dl_dir
  # fi
fi

if [ $stage -le 1 ] && [ $stop_stage -ge 1 ]; then
  log "Stage 1: Prepare manifests"
  mkdir -p data/manifests

  # lhotse prepare bookbot-huggingface $dl_dir/timit data/manifests
  lhotse prepare bookbot-huggingface $dl_dir/libriphone data/manifests --normalize-words=true
  # lhotse prepare bookbot-huggingface $dl_dir/common-voice-13_0-en-v1 data/manifests
  # lhotse prepare bookbot-huggingface $dl_dir/bookbot_en_phonemes data/manifests
  # lhotse prepare bookbot-huggingface $dl_dir/austalk_words_mq data/manifests
  # lhotse prepare bookbot-huggingface $dl_dir/sc_cw_children data/manifests
  # lhotse prepare bookbot-huggingface $dl_dir/l2-arctic data/manifests
  # lhotse prepare bookbot-huggingface $dl_dir/speechocean762 data/manifests
  lhotse prepare musan $dl_dir/musan data/manifests
  # lhotse prepare hallway $dl_dir/audio_splits data/manifests
fi

if [ $stage -le 2 ] && [ $stop_stage -ge 2 ]; then
  log "Stage 2: Compute fbanks"
  mkdir -p data/fbank

  # ./local/compute_fbank_timit.py
  ./local/compute_fbank_libriphone.py
  # ./local/compute_fbank_commonvoice.py
  # ./local/compute_fbank_bookbot.py
  # ./local/compute_fbank_austalk.py
  # ./local/compute_fbank_sccw.py
  # ./local/compute_fbank_l2.py
  # ./local/compute_fbank_speechocean.py
  ./local/compute_fbank_musan.py
  # ./local/compute_fbank_hallway.py
fi

if [ $stage -le 3 ] && [ $stop_stage -ge 3 ]; then
  log "Stage 3: Prepare phone based lang"
  lang_dir=data/lang_phone
  mkdir -p $lang_dir

  (echo '!SIL SIL'; echo '<SPOKEN_NOISE> SPN'; echo '<UNK> SPN'; ) |
  # TODO: check format
    cat - $dl_dir/lm/librispeech-lexicon.txt |
    sort | uniq > $lang_dir/lexicon.txt

  if [ ! -f $lang_dir/L_disambig.pt ]; then
    ./local/prepare_lang.py --lang-dir $lang_dir
  fi

  if [ ! -f $lang_dir/L.fst ]; then
    log "Converting L.pt to L.fst"
    ./shared/convert-k2-to-openfst.py \
      --olabels aux_labels \
      $lang_dir/L.pt \
      $lang_dir/L.fst
  fi

  if [ ! -f $lang_dir/L_disambig.fst ]; then
    log "Converting L_disambig.pt to L_disambig.fst"
    ./shared/convert-k2-to-openfst.py \
      --olabels aux_labels \
      $lang_dir/L_disambig.pt \
      $lang_dir/L_disambig.fst
  fi
fi