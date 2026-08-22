// GENERATED FILE - do not edit by hand.
// Source: out/BinaryMembershipV3.sol/BinaryMembershipV3.json
// Regenerate: forge build && npm --prefix web run gen:abi

export const BINARY_MEMBERSHIP_ABI = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "_asset",
        "type": "address",
        "internalType": "contract IERC20Metadata"
      },
      {
        "name": "_priceOracle",
        "type": "address",
        "internalType": "contract IAssetUsdPriceOracle"
      },
      {
        "name": "_maxPriceAge",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "_treasury",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_companyWallet",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_admin",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_adminDelay",
        "type": "uint48",
        "internalType": "uint48"
      },
      {
        "name": "_designatedRoot",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "DEFAULT_ADMIN_ROLE",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_AWARD_CAP_BPS",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_LIVE_PATH",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_SPONSOR_WALK",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_STAGES",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_TREE_DEPTH",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "OPERATOR_ROLE",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "PAUSER_ROLE",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "TREASURY_ROLE",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "acceptDefaultAdminTransfer",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "asset",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IERC20"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "assetUnit",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "awardCapBps",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "awardRecords",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "member",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "timestamp",
        "type": "uint64",
        "internalType": "uint64"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "beginDefaultAdminTransfer",
    "inputs": [
      {
        "name": "newAdmin",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "cancelDefaultAdminTransfer",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "changeDefaultAdminDelay",
    "inputs": [
      {
        "name": "newDelay",
        "type": "uint48",
        "internalType": "uint48"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "companyWallet",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "configureStages",
    "inputs": [
      {
        "name": "fees",
        "type": "uint256[6]",
        "internalType": "uint256[6]"
      },
      {
        "name": "nodeRewards",
        "type": "uint256[6]",
        "internalType": "uint256[6]"
      },
      {
        "name": "treeSlots",
        "type": "uint256[6]",
        "internalType": "uint256[6]"
      },
      {
        "name": "treeDepths",
        "type": "uint256[6]",
        "internalType": "uint256[6]"
      },
      {
        "name": "rolloversForAward",
        "type": "uint256[6]",
        "internalType": "uint256[6]"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "configured",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "currentWeek",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "cycleGuardEnabled",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "defaultAdmin",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "defaultAdminDelay",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint48",
        "internalType": "uint48"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "defaultAdminDelayIncreaseWait",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint48",
        "internalType": "uint48"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "designatedRoot",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "enrollStageRoot",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "findOpenSlot",
    "inputs": [
      {
        "name": "root",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "findPlacementSlot",
    "inputs": [
      {
        "name": "sponsor",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "findSponsorSlot",
    "inputs": [
      {
        "name": "sponsor",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "fundTreasury",
    "inputs": [
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getAwardInfo",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "totalAwarded",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "lastAwardedRollover",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "rolloverCount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "nextMilestone",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "eligible",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getAwardRecordCount",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getCurrentWeekSponsorCount",
    "inputs": [
      {
        "name": "sponsor",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getMember",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct BinaryMembershipV1.Member",
        "components": [
          {
            "name": "active",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "sponsor",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "joinedAt",
            "type": "uint64",
            "internalType": "uint64"
          },
          {
            "name": "totalEarned",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getRoleAdmin",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getStageConfig",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct BinaryMembershipV1.StageConfig",
        "components": [
          {
            "name": "fee",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "nodeReward",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "treeSlots",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "treeDepth",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "rolloversForAward",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getStageMembership",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct BinaryMembershipV1.StageMembership",
        "components": [
          {
            "name": "enrolled",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "parent",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "side",
            "type": "uint8",
            "internalType": "enum BinaryMembershipV1.Side"
          },
          {
            "name": "left",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "right",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "slotsFilledBelow",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "rolloverCount",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "lastAwardedRollover",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "stageEarnings",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "totalAwarded",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getTreeInfo",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "left",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "right",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "slotsFilledBelow",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "rolloverCount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "lastAwardedRollover",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "stageEarnings",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "grantPhysicalAward",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "grantRole",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "hasRole",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "isSlotAvailable",
    "inputs": [
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "joinAnyStageWithMaxPayment",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      },
      {
        "name": "maximumPayment",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "joinStage",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "joinStageWithMaxPayment",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      },
      {
        "name": "maximumPayment",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "latestAssetPriceUsd",
    "inputs": [],
    "outputs": [
      {
        "name": "priceUsd18",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "updatedAt",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "maxPriceAge",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "memberCount",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "members",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "active",
        "type": "bool",
        "internalType": "bool"
      },
      {
        "name": "sponsor",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "joinedAt",
        "type": "uint64",
        "internalType": "uint64"
      },
      {
        "name": "totalEarned",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "owner",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "pause",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "paused",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "pendingDefaultAdmin",
    "inputs": [],
    "outputs": [
      {
        "name": "newAdmin",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "schedule",
        "type": "uint48",
        "internalType": "uint48"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "pendingDefaultAdminDelay",
    "inputs": [],
    "outputs": [
      {
        "name": "newDelay",
        "type": "uint48",
        "internalType": "uint48"
      },
      {
        "name": "schedule",
        "type": "uint48",
        "internalType": "uint48"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "pendingTreasury",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "priceOracle",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IAssetUsdPriceOracle"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "quoteStagePayment",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "feeAmount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "rewardAmount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "priceUsd18",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "updatedAt",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "register",
    "inputs": [
      {
        "name": "sponsor",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "registerAtStageWithMaxPayment",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "sponsor",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      },
      {
        "name": "maximumPayment",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "registerWithMaxPayment",
    "inputs": [
      {
        "name": "sponsor",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      },
      {
        "name": "maximumPayment",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "renounceRole",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "revokeRole",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "rollbackDefaultAdminDelay",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setAwardCapBps",
    "inputs": [
      {
        "name": "newCapBps",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setCompanyWallet",
    "inputs": [
      {
        "name": "newCompanyWallet",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setCycleGuardEnabled",
    "inputs": [
      {
        "name": "enabled",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setStageOpen",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "open",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setTreasury",
    "inputs": [
      {
        "name": "newTreasury",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "stageAnchor",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "stageClosed",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "stageMemberships",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "enrolled",
        "type": "bool",
        "internalType": "bool"
      },
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      },
      {
        "name": "left",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "right",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "slotsFilledBelow",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "rolloverCount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "lastAwardedRollover",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "stageEarnings",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "totalAwarded",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "stages",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "fee",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "nodeReward",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "treeSlots",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "treeDepth",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "rolloversForAward",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "supportsInterface",
    "inputs": [
      {
        "name": "interfaceId",
        "type": "bytes4",
        "internalType": "bytes4"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalAwardsPaid",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalPoolPaid",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalTreasuryPaid",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "treasury",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "unpause",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "updateAwardThreshold",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "newRolloversForAward",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "updateStageFee",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "newFee",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "newNodeReward",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "weeklySponsorCount",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "weeklyTopCount",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "weeklyTopSponsor",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "withdrawTreasury",
    "inputs": [
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "AwardCapUpdated",
    "inputs": [
      {
        "name": "oldCapBps",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "newCapBps",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "AwardThresholdUpdated",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "oldThreshold",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "newThreshold",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CompanyProfitWithdrawn",
    "inputs": [
      {
        "name": "companyWallet",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CompanyWalletUpdated",
    "inputs": [
      {
        "name": "oldCompanyWallet",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "newCompanyWallet",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CycleGuardToggled",
    "inputs": [
      {
        "name": "enabled",
        "type": "bool",
        "indexed": false,
        "internalType": "bool"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "DefaultAdminDelayChangeCanceled",
    "inputs": [],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "DefaultAdminDelayChangeScheduled",
    "inputs": [
      {
        "name": "newDelay",
        "type": "uint48",
        "indexed": false,
        "internalType": "uint48"
      },
      {
        "name": "effectSchedule",
        "type": "uint48",
        "indexed": false,
        "internalType": "uint48"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "DefaultAdminTransferCanceled",
    "inputs": [],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "DefaultAdminTransferScheduled",
    "inputs": [
      {
        "name": "newAdmin",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "acceptSchedule",
        "type": "uint48",
        "indexed": false,
        "internalType": "uint48"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "MemberRegistered",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "sponsor",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "memberId",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "NodeRewardPaid",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "fromMember",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "Paused",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PhysicalAwardGranted",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "recordIndex",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "RoleAdminChanged",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "previousAdminRole",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "newAdminRole",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "RoleGranted",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "sender",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "RoleRevoked",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "sender",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "Rollover",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "rolloverCount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "StageAnchorSet",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "anchor",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "StageFeeUpdated",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "oldFee",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "newFee",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "oldNodeReward",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "newNodeReward",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "StageJoined",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "parent",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "indexed": false,
        "internalType": "enum BinaryMembershipV1.Side"
      },
      {
        "name": "fee",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "StageToggled",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "open",
        "type": "bool",
        "indexed": false,
        "internalType": "bool"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "StagesConfigured",
    "inputs": [],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TreasuryAddressUpdated",
    "inputs": [
      {
        "name": "oldTreasury",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "newTreasury",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TreasuryFunded",
    "inputs": [
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TreasuryWithdrawalSplit",
    "inputs": [
      {
        "name": "totalAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "treasuryAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "companyAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TreasuryWithdrawn",
    "inputs": [
      {
        "name": "to",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "Unpaused",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AccessControlBadConfirmation",
    "inputs": []
  },
  {
    "type": "error",
    "name": "AccessControlEnforcedDefaultAdminDelay",
    "inputs": [
      {
        "name": "schedule",
        "type": "uint48",
        "internalType": "uint48"
      }
    ]
  },
  {
    "type": "error",
    "name": "AccessControlEnforcedDefaultAdminRules",
    "inputs": []
  },
  {
    "type": "error",
    "name": "AccessControlInvalidDefaultAdmin",
    "inputs": [
      {
        "name": "defaultAdmin",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "AccessControlUnauthorizedAccount",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "neededRole",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ]
  },
  {
    "type": "error",
    "name": "AlreadyEnrolledInStage",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "AlreadyRegistered",
    "inputs": []
  },
  {
    "type": "error",
    "name": "AwardExceedsCap",
    "inputs": [
      {
        "name": "maxAllowed",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "requested",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "EnforcedPause",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ExpectedPause",
    "inputs": []
  },
  {
    "type": "error",
    "name": "FuturePrice",
    "inputs": [
      {
        "name": "updatedAt",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "currentTimestamp",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "InsufficientPendingTreasury",
    "inputs": [
      {
        "name": "available",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "requested",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "InvalidAwardCap",
    "inputs": [
      {
        "name": "bps",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "InvalidBoardGeometry",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "slots",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "depth",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "InvalidFeeConfig",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidPrice",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidSide",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidStage",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "MaximumPaymentRequired",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NoPlacementAvailable",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "NotDesignatedRoot",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotRegistered",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ParentNotInStage",
    "inputs": [
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "ParentOrphanedByCycle",
    "inputs": [
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "ParentPathTooDeep",
    "inputs": [
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "PaymentExceedsMaximum",
    "inputs": [
      {
        "name": "required",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "maximum",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "PayoutWalletCollision",
    "inputs": [
      {
        "name": "wallet",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "PreviousStageRequired",
    "inputs": [
      {
        "name": "requiredStageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "RolloversNotMet",
    "inputs": [
      {
        "name": "required",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "current",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "RootMustStartAtStageOne",
    "inputs": []
  },
  {
    "type": "error",
    "name": "SafeCastOverflowedUintDowncast",
    "inputs": [
      {
        "name": "bits",
        "type": "uint8",
        "internalType": "uint8"
      },
      {
        "name": "value",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "SafeERC20FailedOperation",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "SlotOccupied",
    "inputs": [
      {
        "name": "parent",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum BinaryMembershipV1.Side"
      }
    ]
  },
  {
    "type": "error",
    "name": "SponsorChainExhausted",
    "inputs": [
      {
        "name": "sponsor",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "SponsorNotRegistered",
    "inputs": []
  },
  {
    "type": "error",
    "name": "StageAnchorNotSet",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "StageClosed",
    "inputs": [
      {
        "name": "stageId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "StagesAlreadyConfigured",
    "inputs": []
  },
  {
    "type": "error",
    "name": "StagesNotConfigured",
    "inputs": []
  },
  {
    "type": "error",
    "name": "StalePrice",
    "inputs": [
      {
        "name": "updatedAt",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "currentTimestamp",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "TransactionExpired",
    "inputs": [
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "currentTimestamp",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "TransferAmountMismatch",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ZeroAddress",
    "inputs": []
  }
] as const;
