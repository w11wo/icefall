#!/usr/bin/env bash

log() {
  # This function is from espnet
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

cd egs/librispeech/ASR

repo_url=https://huggingface.co/csukuangfj/icefall-asr-librispeech-pruned-transducer-stateless3-2022-04-29

log "Downloading pre-trained model from $repo_url"
git lfs install
git clone $repo_url
repo=$(basename $repo_url)

log "Display test files"
tree $repo/
soxi $repo/test_wavs/*.wav
ls -lh $repo/test_wavs/*.wav

pushd $repo/exp
ln -s pretrained-epoch-25-avg-6.pt pretrained.pt
popd

for sym in 1 2 3; do
  log "Greedy search with --max-sym-per-frame $sym"

  ./pruned_transducer_stateless3/pretrained.py \
    --method greedy_search \
    --max-sym-per-frame $sym \
    --checkpoint $repo/exp/pretrained.pt \
    --bpe-model $repo/data/lang_bpe_500/bpe.model \
    $repo/test_wavs/1089-134686-0001.wav \
    $repo/test_wavs/1221-135766-0001.wav \
    $repo/test_wavs/1221-135766-0002.wav
done

for method in modified_beam_search beam_search fast_beam_search; do
  log "$method"

  ./pruned_transducer_stateless3/pretrained.py \
    --method $method \
    --beam-size 4 \
    --checkpoint $repo/exp/pretrained.pt \
    --bpe-model $repo/data/lang_bpe_500/bpe.model \
    $repo/test_wavs/1089-134686-0001.wav \
    $repo/test_wavs/1221-135766-0001.wav \
    $repo/test_wavs/1221-135766-0002.wav
done
