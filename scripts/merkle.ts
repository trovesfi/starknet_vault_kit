import { BytesLike, HexString, toHex } from "@ericnordelo/strk-merkle-tree/dist/bytes";
import { MultiProof, processMultiProof, processProof } from "@ericnordelo/strk-merkle-tree/dist/core";
import { standardLeafHash } from "@ericnordelo/strk-merkle-tree/dist/hashes";
import { MerkleTreeData, MerkleTreeImpl } from "@ericnordelo/strk-merkle-tree/dist/merkletree";
import { MerkleTreeOptions } from "@ericnordelo/strk-merkle-tree/dist/options";
import { ValueType } from "@ericnordelo/strk-merkle-tree/dist/serde";
import { validateArgument } from "@ericnordelo/strk-merkle-tree/src/utils/errors";
import { num } from "starknet";
import * as starknet from "@scure/starknet";

export interface LeafData {
  id: bigint,
  data: bigint[]
}

function hash_leaf(leaf: LeafData) {
  if (leaf.data.length < 1) {
    throw new Error("Invalid leaf data");
  }
  let firstElement = leaf.data[0];
  let value = firstElement;
  for (let i=1; i < leaf.data.length; i++) {
    value = pedersen_hash(value, leaf.data[i]);
  }
  return `0x${num.toHexString(value).replace(/^0x/, '').padStart(64, '0')}`;
}

function pedersen_hash(a: bigint, b: bigint): bigint {
  return BigInt(starknet.pedersen(a, b).toString());
}


export interface StandardMerkleTreeData<T extends any> extends MerkleTreeData<T> {
  format: 'standard-v1';
  leafEncoding: ValueType[];
}

export class StandardMerkleTree extends MerkleTreeImpl<LeafData> {
  protected constructor(
    protected readonly tree: HexString[],
    protected readonly values: StandardMerkleTreeData<LeafData>['values'],
    protected readonly leafEncoding: ValueType[],
  ) {
    super(tree, values, leaf => {
      return hash_leaf(leaf)
    });
  }

  static of(
    values: LeafData[],
    leafEncoding: ValueType[] = [],
    options: MerkleTreeOptions = {},
  ): StandardMerkleTree {
    // use default nodeHash (standardNodeHash)
    const [tree, indexedValues] = MerkleTreeImpl.prepare(values, options, leaf => {
      return hash_leaf(leaf)
    });
    return new StandardMerkleTree(tree, indexedValues, leafEncoding);
  }

  static verify<T extends any[]>(root: BytesLike, leafEncoding: ValueType[], leaf: T, proof: BytesLike[]): boolean {
    // use default nodeHash (standardNodeHash) for processProof
    return toHex(root) === processProof(standardLeafHash(leafEncoding, leaf), proof);
  }

  static verifyMultiProof<T extends any[]>(
    root: BytesLike,
    leafEncoding: ValueType[],
    multiproof: MultiProof<BytesLike, T>,
  ): boolean {
    // use default nodeHash (standardNodeHash) for processMultiProof
    return (
      toHex(root) ===
      processMultiProof({
        leaves: multiproof.leaves.map(leaf => standardLeafHash(leafEncoding, leaf)),
        proof: multiproof.proof,
        proofFlags: multiproof.proofFlags,
      })
    );
  }

  dump(): StandardMerkleTreeData<LeafData> {
    return {
      format: 'standard-v1',
      leafEncoding: this.leafEncoding,
      tree: this.tree,
      values: this.values,
    };
  }
}
