const bre = require("@nomiclabs/buidler");
const { expect } = require("chai");

async function main() {
    const Test = await ethers.getContractFactory("Test");
    const test = await Test.deploy();
    await test.deployed();

    let doTest = async (proof, root) => {
        let res = await test.prove(proof);
        expect(res).to.equal(root);
    };

    // a=b, b=c
    {
        let root = '0x7d1c3aaf4be9e074ec8a25b88f1e33f61aebd2b239d2506ccd2f9476080389b1';

        // prove a
        await doTest(
            "0x0000013ac225168df54212a25c1c01fd35bebfea408fdac2e31ddd6f80a4bbf9a5f1cb01620f60e2ba9c7804ddaad28e769649f0cfd71246f0ab6d1d56fd8622a7798f42a96c6f",
            root,
        );
    }

    // perl -E 'for $i (1..1000) { say "$i,$i" }' | ./quadb import
    {
        let root = '0x59b88b76092cc8386fcf4e7f7e28530489d7eacdfae773914ec5516cb052a1d1';

        // prove 3
        await doTest(
            "0x00000c2a80e1ef1d7842f27f2e6be0972bb708b9a135c38860dbe73c27c3486c34f4de01330f635bf4680940616103d08b6a99f5ecddf60d1f090e196d234a3cd2b5f2247684dfe0304787b4dd9e0cfd0d409ea1dbd66d74c70ad4a042786c5c00911b2489f87bdbd60cf8e37b1cc0ed48ded10e54956079a67fd528351491694ba64416c56f607f9fb9737cc3243ac1b51e174f48c360bbbfd15c0651892c59f27853d0819b6c64c019e7090f67531a0f78d1d8e1bff074df72e037981d3c95073ff34e9bc8140050c80c92954bd2704d297f51504485f2fb03907a829a77eee5dc08b1c8ad3b86e0c6c096c420816e8086e3c2bee5b4c441ac3ec9dd55af540eccf01f0316e7deaaaf52745507cdf188f907a120f5293a3cbd56eea1b33c5dfb5527cee36b95e06a42cc1ebf6e57a260d16a3cdbb373a74f66e424fcd8317934c825ec41f5aa80",
            root,
        );
    }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
