python download_rwkv_7.py

python eval_rwkv.py \
    --tokenized PY007/tokenized_proof_pile_test_neox \
    --dataset-min-tokens 32768 \
    --samples 20 \
    --output-file data/rwkv_7.csv \
    --min-tokens 2048 \
    --max-tokens 12288 \
    --tokens-step 2048 \
    --save-tokenized eval_dataset \
    --truncate \
    -m rwkv_model/RWKV-x070-Pile-168M-20241120-ctx4096 \
    -m rwkv_model/RWKV-x070-Pile-421M-20241127-ctx4096 \
    -m rwkv_model/RWKV-x070-Pile-1.47B-20241210-ctx4096