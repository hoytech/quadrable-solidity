pragma solidity ^0.6.0;

import "@nomiclabs/buidler/console.sol";

import "./BytesLib.sol";

library Quadrable {
    enum StrandType {
        Leaf, // = 0,
        WitnessLeaf, // = 1,
        WitnessEmpty, // = 2,
        Unused3,
        Unused4,
        Unused5,
        Unused6,
        Unused7,
        Unused8,
        Unused9,
        Unused10,
        Unused11,
        Unused12,
        Unused13,
        Unused14,
        Invalid // = 15,
    }

    function importProof(bytes memory raw) internal returns (bytes32) {
        uint256 offset = 0;
        uint256 numStrands = 0;

        require(BytesLib.toUint8(raw, offset++) == 0, "Only CompactNoKeys encoding supported");

        // Setup strand state

        while (true) {
            uint256 rawStrandOffset = offset;
            StrandType strandType = StrandType(BytesLib.toUint8(raw, offset++));
            if (strandType == StrandType.Invalid) break;

            uint8 depth = BytesLib.toUint8(raw, offset++);
            bytes32 keyHash = BytesLib.toBytes32(raw, offset);
            offset += 32;

            bytes32 valHash;

            if (strandType == StrandType.Leaf) {
                uint256 valLen = 0;
                uint8 b;
                do {
                    b = BytesLib.toUint8(raw, offset++); 
                    valLen = (valLen << 7) | (b & 0x7F);
                } while ((b & 0x80) != 0);

                assembly { valHash := keccak256(add(add(raw, 0x20), offset), valLen) }

                offset += valLen;
            } else if (strandType == StrandType.WitnessLeaf) {
                valHash = BytesLib.toBytes32(raw, offset);
                offset += 32;
            }

            uint256 strandStateMemOffset;
            assembly {
                strandStateMemOffset := add(mload(0x40), mul(64, numStrands)) // FIXME shift left
            }

            bytes32 nodeHash;

            if (strandType == StrandType.WitnessEmpty) {
                nodeHash = 0x0;
            } else {
                assembly {
                    // Temporarily arrange it so we can compute strand nodeHash in-place
                    mstore(strandStateMemOffset, keyHash)
                    mstore(add(strandStateMemOffset, 32), valHash)
                    mstore8(add(strandStateMemOffset, 64), 0) // free memory not guaranteed to be 0
                    nodeHash := keccak256(strandStateMemOffset, 65)

                    // Now write out the nodeHash over-top
                    mstore(strandStateMemOffset, nodeHash)
                }
            }

            numStrands++; // happens before we generate strandState, since next points to following

            // [4 bytes: rawStrandOffset] [1 byte: depth] [1 byte: merged] [4 bytes: next]
            uint256 strandState = (rawStrandOffset << (6*8)) | (depth << (5*8)) | numStrands;

            assembly {
                mstore(add(strandStateMemOffset, 32), strandState) // linked list pointer
            }
        }

        // Bump free memory pointer to skip over strand state

        uint256 strandStateOffset;
        assembly {
            strandStateOffset := mload(0x40)
            mstore(0x40, add(mload(0x40), mul(64, numStrands))) // FIXME shift left
        }

        if (numStrands == 0) return 0;

        // Make last strand's next point to 0xFFFFFFFF (sentinel null value)

        assembly {
            let lastStrandStateAddr := sub(mload(0x40), 0x20)
            mstore(lastStrandStateAddr, or(mload(lastStrandStateAddr), 0xFFFFFFFF))
        }



        // Process commands

        uint256 currStrand = numStrands - 1;

        while (offset < raw.length) {
            uint8 cmd = BytesLib.toUint8(raw, offset++);
            console.log(cmd);

            if (cmd == 0) {
                // merge
            } else if ((cmd & 0x80) != 0) {
                // hashing
                bool started = false;

                for (uint i=0; i<7; i++) {
                    if (started) {
                        if ((cmd & 1) != 0) {
                            // HashProvided
                        } else {
                            // HashEmpty
                        }
                    } else {
                        if ((cmd & 1) != 0) started = true;
                    }

                    cmd >>= 1;
                }
            } else {
                // jump
            }
        }


        return 0;

        // Strand

        // keyHash
        // val

        // nodeHash
        // currDepth
        // next
        // nodeId
    }
}
