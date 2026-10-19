# Cross repo pin map

This map is read from the committed `Cargo.lock` and `Cargo.toml` of each repository in the stack, not from release notes. Every edge carries the commit the consumer beneath it resolves for the repository above it, as cargo recorded it in the lockfile, or the word path where the consumer builds a sibling checkout through a path dependency. Q-Crypto sits at the root because every repository signs and hashes through it. The stack runs on one line. The node, the SDKs, the CLI, the benchmark, the contract language and the conformance runner all resolve the same Q-Crypto, QVM, QRC-CONSENSUS and Quantova-Chain commits.

```mermaid
graph TD
    QCRYPTO["Q-Crypto<br/>46f7077"]
    QVM["QVM<br/>bf20712"]
    QRC["QRC-CONSENSUS<br/>fe6d36c"]
    QPROVER["q-prover<br/>ef1747f"]
    QLC["Q-Lightclient<br/>7f2259a"]
    CHAIN["Quantova-Chain<br/>fca2d70"]
    QUANTA["Quanta-Smart-Contract-language"]
    QCORERS["QCore.rs<br/>d2112c8"]
    QCOREJS["QCore.js"]
    QCOREPY["QCore.py"]
    CLI["quantova-cli"]
    BENCH["Quantova-Bench"]
    CONF["Quantova-Conformance"]
    ORACLE["Q-Oracle"]

    QCRYPTO -->|46f7077| QVM
    QCRYPTO -->|46f7077| QRC
    QCRYPTO -->|46f7077| QPROVER
    QCRYPTO -->|46f7077| CHAIN
    QCRYPTO -->|46f7077| QUANTA
    QCRYPTO -->|46f7077| QCORERS
    QCRYPTO -->|46f7077| QCOREJS
    QCRYPTO -->|46f7077| QCOREPY
    QCRYPTO -->|46f7077| CLI
    QCRYPTO -->|46f7077| BENCH
    QCRYPTO -->|46f7077| CONF
    QCRYPTO -->|46f7077| ORACLE

    QVM -->|bf20712| CHAIN
    QVM -->|bf20712| QUANTA
    QVM -->|bf20712| QCORERS
    QVM -->|bf20712| QCOREJS
    QVM -->|bf20712| QCOREPY
    QVM -->|bf20712| CLI
    QVM -->|bf20712| BENCH

    QRC -->|fe6d36c| CHAIN
    QRC -->|fe6d36c| QCORERS
    QRC -->|fe6d36c| QCOREJS
    QRC -->|fe6d36c| QCOREPY
    QRC -->|fe6d36c| CLI
    QRC -->|fe6d36c| BENCH

    CHAIN -->|fca2d70| QCORERS
    CHAIN -->|fca2d70| QCOREJS
    CHAIN -->|fca2d70| QCOREPY
    CHAIN -->|fca2d70| CLI
    CHAIN -->|fca2d70| BENCH
    CHAIN -->|fca2d70| CONF

    QCORERS -.->|path| QCOREJS
    QCORERS -.->|path| QCOREPY
    QCORERS -.->|path| CLI
    QRC -.->|path| ORACLE
    CHAIN -.->|path| ORACLE
    QPROVER -.->|path| ORACLE
    QLC -.->|path| ORACLE

    classDef root fill:#0b3d2e,stroke:#0b3d2e,color:#ffffff
    classDef integ fill:#1f4e79,stroke:#1f4e79,color:#ffffff
    classDef leaf fill:#6b3fa0,stroke:#6b3fa0,color:#ffffff
    classDef airlock fill:#8a5a00,stroke:#8a5a00,color:#ffffff
    class QCRYPTO root
    class CHAIN integ
    class BENCH,CONF leaf
    class ORACLE airlock
```

## The pins in use

Q-Crypto is resolved at 46f70778a505a495adb3a1805620802b380ce465 by every lockfile in the map, and no lockfile carries a second Q-Crypto commit.

QVM is resolved at bf2071260666bbf6779edb7f150d1e7cb2c2491b by the node, the contract language, the three QCore packages, the CLI and the benchmark.

QRC-CONSENSUS is resolved at fe6d36c335f985358df3eba0774f4094ec2d9c31 by the node, the three QCore packages, the CLI and the benchmark.

Quantova-Chain is resolved at fca2d70dcd5c20a44bd1261dfb02faacba3bfcdd by the three QCore packages, the CLI, the benchmark and the conformance runner.

QCore.rs is a path dependency of QCore.js, QCore.py and quantova-cli. Path dependencies leave no commit in a lockfile, so each of those repositories declares the QCore.rs commit d2112c88b6b31d84f0d27d122b9b38dfd561eabb in its `cross-repo-pins` file, and its workflows check that commit out beside it.

Q-Oracle builds Q-Lightclient, QRC-CONSENSUS, Quantova-Chain and q-prover crates through path dependencies on sibling checkouts. Its workflow checks out Q-Lightclient 7f2259a2e03594689a4132c7ecc07a85b347312d, QRC-CONSENSUS fe6d36c335f985358df3eba0774f4094ec2d9c31, Quantova-Chain fca2d70dcd5c20a44bd1261dfb02faacba3bfcdd and q-prover ef1747f8d3188049ffd4728c8a62721fa0882193, so those edges are pinned by the workflow and not by a lockfile.

QVRF is not built by any repository in the map.

## How the gate holds the map together

Every shared job builds with `--locked`, so no dependency resolves fresh. The pin agreement gate reads every git source in the lockfile and fails when a source names no rev or tag, when a rev is not a prefix of the commit it resolved to, or when one repository resolves to more than one commit. When a repository carries a `cross-repo-pins` file the gate also checks every declared commit or tag against the lockfile and requires every path dependency that leaves the repository to be declared. `docs/pin-agreement.md` describes the rules and the self test.
