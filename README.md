# LongMamba
This repo contains my exploration on Mamba's context scaling. It includes code to: 1. train Mamba on longer context 2. evaluate Mamba's PPL on the proof pile test set. 3. perform needle in a haystack test (pass-key retrieval).
## Install
<details>
  <summary>Code</summary>
```bash
conda create -n longmamba python=3.10 -y
conda activate longmamba
pip3 install torch --index-url https://download.pytorch.org/whl/cu118
pip install causal-conv1d>=1.1.0
pip install mamba-ssm
pip install -r requirements.txt
```
</details>

## Mamba Cannot Directly Handle Longer Context
We first run Mamba on the proof pile test set and note down the average PPL. It is observed that the PPL explodes when the context length increases. 
<details>
  <summary>Code</summary>

```bash
python eval.py \
    --tokenized PY007/tokenized_proof_pile_test_neox \
    --dataset-min-tokens 32768 \
    --samples 20 \
    --output-file data/original_mamba.csv \
    --min-tokens 2048 \
    --max-tokens 12288 \
    --tokens-step 2048 \
    --truncate \
    -m state-spaces/mamba-2.8b-slimpj \
    -m state-spaces/mamba-2.8b \
    -m state-spaces/mamba-1.4b \
    -m state-spaces/mamba-790m \
    -m state-spaces/mamba-370m \
    -m state-spaces/mamba-130m
python plot.py --xmax 12288 --ymax 20 data/original_mamba.csv
```
</details>
<img src="data/original_mamba.csv.png" alt="PPL explode when increasing the context length" width="500"/>

To further validates that phenomenon, let's look at below plot from [Mamba's ICLR rebuttal](https://openreview.net/forum?id=AL1fq05o7H) (unfortunately the paper not accepted). It was generated by taking the validation set of the Pile dataset, feeding in each example with no padding or concatenation, and measuring the loss per token.
<img src="data/mamba-length-extrapolation.png" alt="Mamba ICLR rebuttal"  width="500"/>


## Preliminary Studies
Mamba is only trained on sequence length up to 2048. It is possible that sequence longer than that is OOD for it. But what if we just tweak the positional embeddings to make it think it's still at position 2048, just like what the  positional interpolation is doing to Transformer (https://arxiv.org/abs/2306.15595 and https://kaiokendev.github.io/til)?
The thing is Mamba does not have positional embeddings. It is position-aware simply through its causal RNN-like architecture. But the underlying state space model does have a term to control the discretization of the context, and I find it quite similar to the positional embeddings in Transformer. The Figure 2 from the MambaByte paper gives a very good illustration.

<img src="data/mamba_byte.png" width="500"/>

Let's say we want Mamba to operate in a 4096 context. To make it think it's still operating at 2048, we can simply decrease the delta to one half of the original value.
<details>
  <summary>Code</summary>
```bash
python eval.py \
    --tokenized PY007/tokenized_proof_pile_test_neox \
    --dataset-min-tokens 32768 \
    --samples 20 \
    --output-file data/original_mamba_delta_ratio_0.5.csv \
    --min-tokens 2048 \
    --max-tokens 12288 \
    --tokens-step 2048 \
    --truncate \
    -m state-spaces/mamba-2.8b-slimpj \
    --delta_ratio 0.5
python plot.py --xmax 12288 --ymax 20 data/original_mamba_delta_ratio_0.5.csv
</details>

And it does seem to work, except that the PPL on short context is now worse.

<img src="data/original_mamba_delta_ratio_0.5.csv.png" alt="PPL explode when increasing the context length" width="500"/>


The very obvious next thing to do is to train Mamba on longer context with the delta value halfed, and we can use mamba directly trained on longer context as a baseline. 
To avoid uncesary counfounders, I choose state-spaces/mamba-2.8b-slimpj and train on a [subsample of slimpajama](DKYoon/SlimPajama-6B), the same dataset that Mamba is pretrained on.
<details>
  <summary>Code</summary>
```bash
accelerate launch --num_processes 8  train.py --batch-size 1 --gradient-accumulate-every 8  --output-dir ./output/slim_delta_1.0_legnth_4096_step_100_lr_2e-5 \
--wandb longmamba  --model state-spaces/mamba-2.8b-slimpj --dataset PY007/tokenized_slim6B_train_neox_4096 --max-train-steps 100   --learning-rate 2e-5
accelerate launch --num_processes 8  train.py --batch-size 1 --gradient-accumulate-every 8  --output-dir ./output/slim_delta_0.5_legnth_4096_step_100_lr_2e-5 \
--wandb longmamba  --model state-spaces/mamba-2.8b-slimpj --dataset PY007/tokenized_slim6B_train_neox_4096 --max-train-steps 100   --learning-rate 2e-5 --delta_ratio 0.5
```
</details>

<img src="data/mamba_half_delta_training.csv.png" width="500">

Turns out halfing the delta value performs worse than the baseline. What suprises me is how good the baseline is doing: it is only trained on 2048 --> 4096 context, but it generalizes to sequence length up to 12288. This is a very good sign that Mamba is capable of handling longer context without bells and whistles! 

## Start Baking
I then train mamba-2.8b-slimpj on 16384 context length, the longest that I can fit with 8 A100 80GB and FSDP Fully Shard enabled. The nice thing is it only taks 9 hours.
<details>
  <summary>Code</summary>
```bash
srun accelerate launch --num_processes 8  finetune.py --batch-size 1 --gradient-accumulate-every 16  --output-dir ./output/2.8B_slim_legnth_16384_step_400_lr_3e-5 \
--wandb longmamba  --model state-spaces/mamba-2.8b-slimpj --dataset PY007/tokenized_slim6B_train_neox_16384  --delta_ratio 1.0 --max-train-steps 400   --learning-rate 3e-5
# Model is uploaded to https://huggingface.co/PY007/LongMamba_16384_bs128_step400
python eval.py \
    --tokenized PY007/tokenized_proof_pile_test_neox \
    --dataset-min-tokens 65536 \
    --samples 20 \
    --output-file data/LongMamba_16384_bs128_step400.csv \
    --min-tokens 2048 \
    --max-tokens 65536 \
    --tokens-step 2048 \
    --truncate \
    -m PY007/LongMamba_16384_bs128_step400 \
    -m state-spaces/mamba-2.8b-slimpj
python plot.py --xmax 65536 --ymin 2 --ymax 10 data/LongMamba_16384_bs128_step400.csv
python plot.py --xmax 65536 --ymin 2 --ymax 4 data/LongMamba_16384_bs128_step400.csv
```
</details>

<img src="data/LongMamba_16384_bs128_step400_large.csv.png" width="500">

A closeer look:

<img src="data/LongMamba_16384_bs128_step400.csv.png" width="500">


This time it is just doing so good. The PPL keeps decreasing till 40K. Even after 40K, it just increase a little bit rather than directly explode.

Only the PPL test is not enought though. We need to see whether can it really memorize things. To do this, I follow [LongLora](https://arxiv.org/abs/2309.12307) and test my model with pass-key retrieval. Here is what the task looks like:

<img src="data/longlora_passkey.png" width="500">

Note that this test is slightly different from https://github.com/gkamradt/LLMTest_NeedleInAHaystack because in this test the haystack is just one sentence repeated N and M times, while in https://github.com/gkamradt/LLMTest_NeedleInAHaystack, the haystack is a an actualy docment.

<details>
  <summary>Code</summary>
```bash
python pass_key.py --max_tokens 16384 --num_tests 5
python pass_key.py --max_tokens 32768 --num_tests 5
```
</details>

<img src="data/heatmap_16384.png" width="500">

It can be observed that the model retrieves nearly perfectly on 16384. We can further test on 32768 tokens, and see if it still works well.

<img src="data/heatmap_32768.png" width="500">

## Next Step


## References
This repository borrows code from the [yarn repo](https://github.com/jquesnelle/yarn).
