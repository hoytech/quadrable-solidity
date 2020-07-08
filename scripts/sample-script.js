const bre = require("@nomiclabs/buidler");
const { expect } = require("chai");

const child_process = require('child_process');

const quadb = '../quadrable/quadb';




let testSpecs = [];

testSpecs.push({
    desc: 'single branch inclusion',
    data: {
        a: 'b',
        b: 'c',
    },
    inc: ['a'],
    non: [],
    err: ['b'],
});


testSpecs.push({
    desc: '1000 records, both types of non-inclusion',
    data: makeData(1000, i => [i+1, i+1]),
    inc: ['3', '4'],
    non: [
        '5000', // WitnessEmpty
        '5001', // WitnessLeaf
    ],
    err: ['b'],
});



testSpecs.push({
    desc: 'long key/value',
    data: {
        ['key'.repeat(100)]: 'value'.repeat(1000),
    },
    inc: ['key'.repeat(100)],
});




testSpecs.push({
    desc: 'put update left side',
    data: {
        a: 'b',
        b: 'c',
    },
    inc: ['a'],
    put: [
        ['a', 'hello'],
    ],
});

testSpecs.push({
    desc: 'put update right side',
    data: {
        a: 'b',
        b: 'c',
    },
    inc: ['b'],
    put: [
        ['b', 'hello'],
    ],
});

testSpecs.push({
    desc: 'put both sides',
    data: {
        a: 'b',
        b: 'c',
    },
    inc: ['a', 'b'],
    put: [
        ['a', 'hello'],
        ['b', 'hello'],
    ],
});

testSpecs.push({
    desc: 'put both sides, other order',
    data: {
        a: 'b',
        b: 'c',
    },
    inc: ['a', 'b'],
    put: [
        ['b', 'hello'],
        ['a', 'hello'],
    ],
});


testSpecs.push({
    desc: '1000 records, update a few of them',
    data: makeData(1000, i => [i+1, i+1]),
    inc: ['200', '201', '202'],
    put: [
        ['200', 'new value for 200'],
        ['201', 'new value for 201'],
        ['202', 'new value for 202'],
    ],
});


testSpecs.push({
    desc: 'add record to WitnessEmpty',
    data: makeData(1000, i => [i+1, i+1]),
    non: ['5000'],
    put: [
        ['5000', 'new value for 5000'],
    ],
});

testSpecs.push({
    desc: 'add record, split WitnessLeaf',
    data: {
        a: 'b',
        b: 'c',
    },
    non: ['x'],
    put: [
        ['x', 'new value for x'],
    ],
});

testSpecs.push({
    desc: 'add record, split WitnessLeaf, with extra branch',
    data: {
        a: 'b',
        b: 'c',
    },
    non: ['y'],
    put: [
        ['y', 'new value for y'],
    ],
});

testSpecs.push({
    desc: '1000 records, add record, split WitnessLeaf',
    data: makeData(1000, i => [i+1, i+1]),
    non: ['5001'],
    put: [
        ['5001', 'new value for 5001'],
    ],
});



async function main() {
    let quadb_dir = './quadb-test-dir';
    let quadb_cmd = `${quadb} --db ${quadb_dir}`;

    child_process.execSync(`mkdir -p ${quadb_dir}`);
    child_process.execSync(`rm -f ${quadb_dir}/*.mdb`);


    let specsDevMode = testSpecs.filter(s => s.dev);
    if (specsDevMode.length) {
        testSpecs = specsDevMode;
        console.log("RUNNING IN DEV MODE");
    }

    let origSpecsLen = testSpecs.length;
    testSpecs = testSpecs.filter(s => !s.skip);
    if (origSpecsLen !== testSpecs.length) console.log("SKIPPING ONE OR MORE TESTS");


    const Test = await ethers.getContractFactory("Test");
    const test = await Test.deploy();
    await test.deployed();

    for (let spec of testSpecs) {
        console.log(`Running test: ${spec.desc}`);

        child_process.execSync(`${quadb_cmd} checkout`);

        let rootHex, proofHex;

        {
            let input = '';

            for (let key of Object.keys(spec.data)) {
                input += `${key},${spec.data[key]}\n`;
            }

            child_process.execSync(`${quadb_cmd} import`, { input, });
            rootHex = child_process.execSync(`${quadb_cmd} root`).toString().trim();

            let proofKeys = (spec.inc || []).concat(spec.non || []).join(' ');

            proofHex = child_process.execSync(`${quadb_cmd} exportProof --hex -- ${proofKeys}`).toString().trim();
        }

        let updateKeys = [];
        let updateVals = [];

        for (let p of (spec.put || [])) {
            updateKeys.push(Buffer.from(p[0]));
            updateVals.push(Buffer.from(p[1]));
        }

        let res = await test.testProof(proofHex, (spec.inc || []).map(i => Buffer.from(i)), updateKeys, updateVals);
        expect(res[0]).to.equal(rootHex);
        for (let i = 0; i < (spec.inc || []).length; i++) {
            let valHex = res[1][i];
            valHex = valHex.substr(2); // remove 0x prefix
            expect(Buffer.from(valHex, 'hex').toString()).to.equal(spec.data[spec.inc[i]]);
        }

        if (spec.non && spec.non.length) {
            let res = await test.testProof(proofHex, spec.non.map(i => Buffer.from(i)), [], []);
            for (let i = 0; i < spec.non.length; i++) {
                expect(res[1][i]).to.equal('0x');
            }
        }

        for (let e of (spec.err || [])) {
            let threw;
            try {
                await test.testProof(proofHex, [Buffer.from(e)], [], []);
            } catch (e) {
                threw = '' + e;
            }
            expect(threw).to.not.be.undefined;
            expect(threw).to.contain("incomplete tree");
        }

        if (spec.put && spec.put.length) {
            let input = '';

            for (let p of (spec.put || [])) {
                input += `${p[0]},${p[1]}\n`;
            }

            child_process.execSync(`${quadb_cmd} import`, { input, });
            let newRootHex = child_process.execSync(`${quadb_cmd} root`).toString().trim();
            expect(res[2]).to.equal(newRootHex);
        }
    }
}


function makeData(n, cb) {
    let output = {};
    for (let i of Array.from(Array(n).keys())) {
        let [k, v] = cb(i);
        output[k] = '' + v;
    }
    return output;
}


main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
