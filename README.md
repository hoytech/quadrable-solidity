## Solidity

As a complement to the [Quadrable C++ implementation](https://github.com/hoytech/quadrable), this repo contains a [Solidity](https://solidity.readthedocs.io/en/v0.6.11/) implementation. Solidity is a programming language for implementing smart contracts on the Ethereum blockchain.

**NOTE**: Although it should still work, this implementation does not track the most recent developments in the Quadrable repo.


## Storage

Since using blockchain storage from a smart contract is very expensive, this implementation does not require it. In fact, avoiding storage is one of the primary reasons you might use Quadrable: An authenticated data-structure allows a smart contract to perform read and write operations on a large data-set, even if that data-set does not exist in the blockchain state at all. All of the functions in the Quadrable solidity library are [pure functions](https://solidity.readthedocs.io/en/v0.6.6/contracts.html#pure-functions).


## Testing

First ensure that the `quadb` binary has been compiled and exists in `../quadrable/`

Next, install dependencies and run tests:

    npm i
    npx buidler test


### Smart Contract Usage

First, copy the `Quadrable.sol` file into your project's `contracts/` directory, and import it:

    import "./Quadrable.sol";

To validate a Quadrable proof in a smart contract, you need two items:

* `bytes encodedProof` - This is a variable-length byte-array, as output by [quadb exportProof](#quadb-exportproof) (must be `HashedKeys` encoding).
* `bytes32 trustedRoot` - This is a hash of a root node from a trusted source (perhaps from storage, or provided by a trusted user).

Once you have these, load the proof into memory with `Quadrable.importProof()`. This creates a new tree and returns a memory address pointing to the root node:

    uint256 rootNodeAddr = Quadrable.importProof(encodedProof);

Use `Quadrable.getNodeHash()` to retrieve the hash of this node and ensure that it is the same as the `trustedRoot`:

    require(Quadrable.getNodeHash(rootNodeAddr) == trustedRoot, "proof invalid");

Because the loaded proof is most likely a partial tree, you must be careful to only access values that were specified when the proof was created (either inclusion or non-inclusion). If you try to access other values, an `incomplete tree` error will be thrown with `require()`.

#### get

Now that you have authenticated the partial tree created from the proof, you can begin to use it. First the key you are interested in must be hashed:

    bytes32 keyHash = keccak256(abi.encodePacked("my key"));

`Quadrable.get()` can be called to lookup values. It returns two items: `found` is a boolean indicating whether the key is present in the tree. If it is true, then `val` will contain the corresponding value for the provided key. If `found` is false, then `val` will be empty (0 length):

    (bool found, bytes memory val) = Quadrable.get(rootNodeAddr, keyHash);

If you need to access a value multiple times, it is preferable to store the result in memory so you don't need to call `Quadrable.get()` multiple times (which is [expensive](#gas-usage)).

When using [integer keys](#integer-keys), do not hash the keys. Instead, use the `Quadrable.encodeInt()` function:

    (bool found, bytes memory val) = Quadrable.get(rootNodeAddr, Quadrable.encodeInt(myInt));

#### put

You can modify the tree with `Quadrable.put()`. This will return a new `rootNodeAddr`, which you should use to overwrite the old root node address (since it is no longer valid):

    rootNodeAddr = Quadrable.put(rootNodeAddr, keyHash, "new val");

`Quadrable.getNodeHash()` can now be used to retrieve the updated root incorporating your modifications:

    bytes32 newTrustedRoot = Quadrable.getNodeHash(rootNodeAddr);

Similar to get, if using integer keys then use the `Quadrable.encodeInt()` function instead of hashing the keys.

#### push

If the partial tree created is [pushable](#pushable-logs) then you can use `Quadrable.push()` to append new items:

    rootNodeAddr = Quadrable.push(rootNodeAddr, "new val");

Note that when pushing no key is required. The value is added to the next pushable index, and the next pushable index is then incremented.

You can retrieve the number of elements in the log by calling `length` (which just returns the next pushable index or 0 if not set):

    uint256 totalItems = Quadrable.length(rootNodeAddr);



### Memory Layout

See the [Strands](#strands) section for details on how the proof decoding algorithm works. The Solidity implementation is similar to the C++ implementation, except that it does not decode the proof to an intermediate format prior to processing. Instead, it directly processes the encoded proof for efficiency reasons.

Because the number of strands is not known in advance and Solidity does not support resizing dynamic memory arrays, the function that parses the strands is careful to not allocate any memory in order to support processing the proof in a single pass. As it executes it builds up a contiguous array of strand elements. Each strand element contains a 32-byte strandState, a keyHash, and a node that will store the leaf for this strand (if any):

    Strand element (128 bytes):
        uint256 strandState: [0 padding...] [1 byte: depth] [1 byte: merged] [4 bytes: next] [4 bytes: nodeAddr]
        [32 bytes: keyHash]
        [64 bytes: possibly containing leaf node for this strand]

The strandState contains the working information needed while processing the proof, and the keyHash for this strand.

Each node is 64 bytes and consists of a 32-byte nodeContents followed by a 32-byte nodeHash. The nodeContents uses the least significant byte to indicate the type of the node, and the rest is specific to the nodeType as follows:

    Node (64 bytes):
        uint256 nodeContents: [0 padding...] [nodeType specific (see below)] [1 byte: nodeType]
                   Leaf: [4 bytes: valAddr] [4 bytes: valLen] [4 bytes: keyHashAddr]
            WitnessLeaf: [4 bytes: keyHashAddr]
                Witness: unused
                 Branch: [4 bytes: parentNodeAddr] [4 bytes: leftNodeAddr] [4 bytes: rightNodeAddr]
        bytes32 nodeHash

* `parentNodeAddr` is not maintained as an invariant: It is only used as a temporary scratch memory area during tree updates, to avoid recursion.



### Limitations of Solidity Implementation

* Only the `HashedKeys` proof encoding is supported. This means that enumeration by key is not possible.
* Unlike the C++ library, the Solidity implementation does not support deletion. This may be implemented in the future, but for now protocols should use some sensible empty-like value if they wish to support removals (such as all 0 bytes, or the empty string). The proof creation code also needs to be updated to be able to create deletion-capable proofs (see [bubbling](#bubbling)).
* The Solidity implementation does *not* use [copy-on-write](#copy-on-write), so multiple versions of the tree can not exist simultaneously. Instead, the tree is updated in-place during modifications (nodes are reused when possible). After a `put()`, the old root node address becomes invalid. This is done to limit the amount of memory consumed.
* Unlike the C++ implementation operations can not be [batched](#operation-batching). This is complicated to do in Solidity because dynamic memory management is difficult. Nevertheless, this may be an area for future optimisation.
* Proofs cannot be created by the Solidity implementation. This should not be necessary for most use-cases.
* Importing large proofs can have [high gas costs](#gas-usage).


### Gas Usage

There are several variables than impact the gas usage of the library:

* Size of the database and distribution of its keys
* Number of records to be proven
* Distribution of *their* keys
* Proportion of inclusion versus non-inclusion proofs
* Length of values

The following is a generated table of gas costs for a simple scenario. For each row, a DB of size N is created with effectively random keys. A single element is selected to be proven (an inclusion proof). The proof size is recorded and this is used to estimate calldata costs. Then the gas costs are measured by the test harness for 3 operations: Importing the proof, looking up the value in the partial tree, and updating the value and computing a new root.

| DB Size | Average Depth | Calldata (gas) | Import (gas) | Query (gas) | Update (gas) | Total (gas) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 0 | 1216 | 2910 | 1622 | 1693 | 7441 |
| 10 | 3.3 | 6368 | 8801 | 3651 | 8376 | 27196 |
| 100 | 6.6 | 7392 | 9073 | 3651 | 8377 | 28493 |
| 1000 | 10 | 11520 | 14264 | 5356 | 13977 | 45117 |
| 10000 | 13.3 | 14624 | 19155 | 7031 | 19518 | 60328 |
| 100000 | 16.6 | 19776 | 23700 | 8031 | 22830 | 74337 |
| 1000000 | 19.9 | 22848 | 25400 | 8697 | 25038 | 81983 |

* Since the element being proven is not necessarily at the average depth of the tree, these values aren't precise but still provide a representative estimate
* The gas usage is roughly proportional to the number of witnesses provided with the proof. Because of logarithmic growth, the DB size can grow quite large without raising the gas cost considerably.
* The calldata estimate is slightly high since it doesn't account for the zero byte discount.
* The import gas includes a copy of the proof from calldata to memory which is needed to call the `Quadrable.importProof()` function. Theoretically this could be optimised, but it currently accounts for only around 1% of the import costs so is not high priority.

Now consider the following test. Here we have setup a DB with 1 million records (the same configuration as the last row in the previous test). Each row creates a proof proving the inclusion of `N` different records. This results in a proof with `N` [strands](#strands). Each of the `N` records is queried and then updated (with no batching).

| Num Strands | Approx Witnesses | Calldata (gas) | Import (gas) | Query (gas) | Update (gas) | Total (gas) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 19.9 | 22848 | 25083 | 8697 | 25038 | 81666 |
| 2 | 39.9 | 41632 | 50833 | 17683 | 51156 | 161304 |
| 4 | 79.7 | 79136 | 97768 | 36112 | 104747 | 317763 |
| 8 | 159.5 | 144736 | 174654 | 70738 | 204839 | 594967 |
| 16 | 318.9 | 260000 | 328373 | 138122 | 398654 | 1125149 |
| 32 | 637.8 | 508768 | 643279 | 278367 | 803794 | 2234208 |
| 64 | 1275.6 | 971712 | 1265301 | 564306 | 1630652 | 4431971 |
| 128 | 2551.2 | 1789600 | 2485351 | 1138851 | 3288189 | 8701991 |

* The number of witnesses is roughly the number of strands times the average depth of the tree (fixed at 19.9). This estimate is slightly high because it doesn't account for the witnesses omited due to [combined proofs](#combined-proofs). Better proxies for this estimate are proof size or (equivalently) calldata gas: Observe that when the number of strands doubles, the calldata gas less than doubles. This effect will become more pronounced with smaller DB sizes or larger number of strands.

In general, the gas cost is proportional to the number of witnesses in the proof, which is roughly the average depth of the tree times the number of values to be proven. To determine the gas cost for calldata, importing the proof, querying, and updating, take this number and multiply it by 5000 (very rough estimate). The gas cost technically isn't linear, since (among other things) the cost of EVM memory increases quadratically, but empirically this estimate seems to hold for reasonable parameter sizes.

For optimistic roll-up applications, proofs only need to be supplied in the case a fraudulent action is detected. If the system is well designed, then game-theoretically the frequency of this should be "never". Because of this, typical gas costs aren't the primary concern. The bigger issue is the worst-case gas usage in the presence of [adversarially selected keys](#proof-bloating). If an attacker manages to make it so costly for the system to verify a fraud proof that it cannot be done within the block-gas limit (the maximum gas that a transaction can consume, at any cost), then there is an opportunity for fraud to be committed.

Let's assume that an attacker can create colliding keyHashes up to a depth of 160 for every element to be proven. Each of these would be extremely computationally expensive -- on the same order as finding distinct private keys with colliding bitcoin/ethereum addresses. In this case, calldata+import+query+update would take around 800k gas for each value. At the time of this writing, the gas block limit is 12.5m, which suggests that around 15 of these worst-case scenario values could be verified. In order to leave a very wide security margin, this suggests that fraud-proof systems should try to use under 15 values for each unit of verification (assuming other gas costs are negligible).
