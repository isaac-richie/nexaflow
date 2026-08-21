// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BinaryMembershipV1
/// @notice 6-stage binary tree membership with real-time upline payouts,
///         rollover cycling, spillover placement, and admin-triggered physical awards.
///
///  Stage flow:
///   1. Member pays `stageFee[stageId]` in `asset` tokens.
///   2. Member is placed in their parent's binary tree (left or right).
///   3. EVERY upline whose board the placement lands on is paid one full
///      `nodeReward` instantly — the walk runs up to `treeDepth` ancestors,
///      because a board is `treeDepth` levels deep. A board owner therefore
///      collects `nodeReward` from every position on their board:
///      6 x nodeReward at stage 0, 14 x nodeReward at stages 1-5.
///   4. Whatever the uplines did not consume goes to treasury. Placements near
///      the top of a fresh tree have fewer ancestors, so treasury keeps more.
///   5. When a member's board is full (6 slots stage 0, 14 slots stages 1-5),
///      they "roll over" — counter increments, fresh board.
///   6. After N rollovers (configurable per stage), admin triggers physical award.
///
///  Solvency: `configureStages` and `updateStageFee` both enforce
///  `treeDepth * nodeReward < fee`, so a full-depth payout can never exceed
///  the fee funding it. Treasury retains 50-58% at the shipped configuration.
///
///  Fee-on-transfer tokens are rejected via exact-balance checks.

contract BinaryMembershipV1 is AccessControlDefaultAdminRules, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────────────────────────
    //  Roles
    // ──────────────────────────────────────────────────────────────────

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ──────────────────────────────────────────────────────────────────
    //  Constants & immutables
    // ──────────────────────────────────────────────────────────────────

    uint256 public constant MAX_STAGES = 6;

    /// @dev Upper bound on a stage's board depth. Keeps the 2^(d+1) slot-count
    ///      check in `configureStages` well clear of overflow, and a board
    ///      deeper than this has no business in this plan.
    uint256 public constant MAX_TREE_DEPTH = 8;

    IERC20 public immutable asset;
    address public treasury;

    /// @notice The only address permitted to take the system root position.
    /// @dev Fixed at deployment. The root is the most valuable position in the
    ///      system — it pays no fee and sits above every board — and `register`
    ///      would otherwise award it to whoever calls first. Pinning it here
    ///      closes the window between deployment and the root's first
    ///      transaction, during which anyone could have claimed it for nothing.
    address public immutable designatedRoot;

    // ──────────────────────────────────────────────────────────────────
    //  Stage configuration
    // ──────────────────────────────────────────────────────────────────

    struct StageConfig {
        uint256 fee; // registration fee for this stage
        uint256 nodeReward; // portion of fee that goes to upline pool
        uint256 treeSlots; // slots below a member (6 for stage 0, 14 for stages 1-5)
        uint256 treeDepth; // levels below member (2 for stage 0, 3 for stages 1-5)
        uint256 rolloversForAward; // rollovers needed before physical award (0 = no award)
    }

    // stageId 0..5 (displayed as stages 1..6 to users)
    StageConfig[MAX_STAGES] public stages;
    bool public configured;

    // ──────────────────────────────────────────────────────────────────
    //  Enums & structs
    // ──────────────────────────────────────────────────────────────────

    enum Side {
        None,
        Left,
        Right
    }

    struct Member {
        bool active;
        address sponsor; // who referred them
        uint64 joinedAt;
        uint256 totalEarned;
    }

    struct StageMembership {
        bool enrolled;
        address parent; // tree parent at this stage
        Side side; // left or right under parent
        address left; // left child
        address right; // right child
        uint256 slotsFilledBelow; // how many descendants placed below this member
        uint256 rolloverCount; // how many times tree completed
        uint256 lastAwardedRollover; // rollover count at which the last award was granted
        uint256 stageEarnings; // total earned at this stage
        uint256 totalAwarded; // cumulative awards received at this stage
    }

    // ──────────────────────────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────────────────────────

    uint256 public memberCount;
    mapping(address => Member) public members;
    // member => stageId => stage membership
    mapping(address => mapping(uint256 => StageMembership)) public stageMemberships;

    // accounting
    uint256 public totalPoolPaid; // total node rewards paid to uplines
    uint256 public totalTreasuryPaid; // total sent to treasury
    uint256 public pendingTreasury; // accumulated treasury portion not yet withdrawn
    uint256 public totalAwardsPaid; // cumulative physical awards granted

    // weekly top sponsor tracking
    uint256 public currentWeek;
    mapping(uint256 => mapping(address => uint256)) public weeklySponsorCount;
    mapping(uint256 => address) public weeklyTopSponsor;
    mapping(uint256 => uint256) public weeklyTopCount;

    // physical award tracking
    struct AwardRecord {
        address member;
        uint256 stageId;
        uint256 amount;
        uint64 timestamp;
    }
    AwardRecord[] public awardRecords;

    /// @notice The board a stage falls back to when a member's sponsor chain
    ///         has not reached that stage yet.
    /// @dev Recorded on the FIRST root enrolled at each stage and never
    ///      overwritten, so it is a stable placement target for the lifetime of
    ///      the stage. Stage 0's anchor is the system root, set at registration.
    ///      Without this the caller has to know which member was seeded as a
    ///      stage root, which is off-chain knowledge the contract already has.
    mapping(uint256 => address) public stageAnchor;

    /// @dev Bound on the sponsor-chain walk. Matches the depth any realistic
    ///      referral chain reaches and keeps the loop gas-bounded.
    uint256 public constant MAX_SPONSOR_WALK = 256;

    /// @dev Maximum number of reciprocal parent links a guarded placement may
    ///      traverse before reaching a stage root. The guard used to inspect
    ///      only `treeDepth` links, so a broken edge just beyond the payout
    ///      board was invisible. A finite whole-path bound closes that bypass
    ///      without reintroducing an unbounded gas walk.
    uint256 public constant MAX_LIVE_PATH = 256;

    // Admin-configurable toggles
    bool public cycleGuardEnabled;
    mapping(uint256 => bool) public stageClosed;

    /// @notice Ceiling on a physical award, in basis points of the member's
    ///         own `stageEarnings` at that stage. Capped at 100%.
    /// @dev This is the structural defence against self-farming the rollover
    ///      threshold. Someone filling their own board with wallets they
    ///      control pays every downline fee themselves, so their cost scales
    ///      with the board while a genuine member's does not — a genuine member
    ///      pays only their own join. Tying the award to earnings therefore
    ///      makes farming unprofitable at every stage without the contract ever
    ///      needing to know who owns which wallet.
    uint256 public constant MAX_AWARD_CAP_BPS = 10_000;
    uint256 public awardCapBps = MAX_AWARD_CAP_BPS;

    // ──────────────────────────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────────────────────────

    event MemberRegistered(address indexed member, address indexed sponsor, uint256 memberId);

    event StageJoined(address indexed member, uint256 indexed stageId, address indexed parent, Side side, uint256 fee);

    event NodeRewardPaid(
        address indexed recipient, address indexed fromMember, uint256 indexed stageId, uint256 amount
    );

    event TreasuryFunded(uint256 amount);

    event Rollover(address indexed member, uint256 indexed stageId, uint256 rolloverCount);

    event PhysicalAwardGranted(address indexed member, uint256 indexed stageId, uint256 amount, uint256 recordIndex);

    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);
    event StagesConfigured();
    event StageFeeUpdated(
        uint256 indexed stageId, uint256 oldFee, uint256 newFee, uint256 oldNodeReward, uint256 newNodeReward
    );
    event AwardThresholdUpdated(uint256 indexed stageId, uint256 oldThreshold, uint256 newThreshold);
    event CycleGuardToggled(bool enabled);
    event StageAnchorSet(uint256 indexed stageId, address indexed anchor);
    event AwardCapUpdated(uint256 oldCapBps, uint256 newCapBps);
    event StageToggled(uint256 indexed stageId, bool open);

    // ──────────────────────────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────────────────────────

    error AlreadyRegistered();
    error NotRegistered();
    error SponsorNotRegistered();
    error StagesAlreadyConfigured();
    error StagesNotConfigured();
    error InvalidStage(uint256 stageId);
    error AlreadyEnrolledInStage(uint256 stageId);
    error PreviousStageRequired(uint256 requiredStageId);
    error SlotOccupied(address parent, Side side);
    error ParentNotInStage(address parent, uint256 stageId);
    error InvalidSide();
    error ZeroAddress();
    error InsufficientPendingTreasury(uint256 available, uint256 requested);
    error TransferAmountMismatch();
    error RolloversNotMet(uint256 required, uint256 current);
    error InvalidFeeConfig();
    error StageClosed(uint256 stageId);
    error ParentOrphanedByCycle(address parent, uint256 stageId);
    error ParentPathTooDeep(address parent, uint256 stageId);
    error AwardExceedsCap(uint256 maxAllowed, uint256 requested);
    error InvalidAwardCap(uint256 bps);
    error NotDesignatedRoot();
    error InvalidBoardGeometry(uint256 stageId, uint256 slots, uint256 depth);
    error StageAnchorNotSet(uint256 stageId);
    error NoPlacementAvailable(uint256 stageId);
    error SponsorChainExhausted(address sponsor, uint256 stageId);
    error PaymentExceedsMaximum(uint256 required, uint256 maximum);

    // ──────────────────────────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────────────────────────

    constructor(IERC20 _asset, address _treasury, address _admin, uint48 _adminDelay, address _designatedRoot)
        AccessControlDefaultAdminRules(_adminDelay, _admin)
    {
        if (address(_asset) == address(0) || _treasury == address(0)) revert ZeroAddress();
        if (_designatedRoot == address(0)) revert ZeroAddress();
        asset = _asset;
        treasury = _treasury;
        designatedRoot = _designatedRoot;
    }

    // ──────────────────────────────────────────────────────────────────
    //  Admin: configure stages (one-time)
    // ──────────────────────────────────────────────────────────────────

    /// @notice Configure all 6 stages. Can only be called once.
    /// @dev Stage 0 = $20 package (6 slots, 2 depth), Stages 1-5 = $60-$4860 (14 slots, 3 depth)
    function configureStages(
        uint256[MAX_STAGES] calldata fees,
        uint256[MAX_STAGES] calldata nodeRewards,
        uint256[MAX_STAGES] calldata treeSlots,
        uint256[MAX_STAGES] calldata treeDepths,
        uint256[MAX_STAGES] calldata rolloversForAward
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (configured) revert StagesAlreadyConfigured();

        for (uint256 i = 0; i < MAX_STAGES; i++) {
            if (fees[i] == 0 || nodeRewards[i] == 0) revert InvalidFeeConfig();
            if (treeSlots[i] == 0 || treeDepths[i] == 0) revert InvalidFeeConfig();

            // A binary board `d` levels deep holds exactly 2^(d+1) - 2 slots:
            // 6 at depth 2, 14 at depth 3. Both fields are written once here
            // and have no setter afterwards, so a mismatched pair would be
            // permanent — it would either make rollover unreachable (slots too
            // high) or fire it before the board is full (slots too low).
            // MAX_TREE_DEPTH keeps the shift bounded.
            if (treeDepths[i] > MAX_TREE_DEPTH) {
                revert InvalidBoardGeometry(i, treeSlots[i], treeDepths[i]);
            }
            if (treeSlots[i] != (1 << (treeDepths[i] + 1)) - 2) {
                revert InvalidBoardGeometry(i, treeSlots[i], treeDepths[i]);
            }
            // A placement at full board depth pays treeDepth uplines one
            // nodeReward each. The fee must cover that with room for treasury.
            if (nodeRewards[i] * treeDepths[i] >= fees[i]) revert InvalidFeeConfig();

            stages[i] = StageConfig({
                fee: fees[i],
                nodeReward: nodeRewards[i],
                treeSlots: treeSlots[i],
                treeDepth: treeDepths[i],
                rolloversForAward: rolloversForAward[i]
            });
        }

        configured = true;
        emit StagesConfigured();
    }

    // ──────────────────────────────────────────────────────────────────
    //  Core: register + join stage
    // ──────────────────────────────────────────────────────────────────

    /// @notice Register as a new member and join stage 0 (stage 1 to users).
    ///         First member calls with sponsor = address(0) to become root.
    /// @param sponsor  Who referred this member (address(0) for root)
    /// @param parent   Tree parent at stage 0 (who they sit under)
    /// @param side     Left or Right under parent
    function register(address sponsor, address parent, Side side) external virtual nonReentrant whenNotPaused {
        _register(sponsor, parent, side, type(uint256).max);
    }

    /// @dev Shared registration path. The maximum-payment argument lets a
    ///      market-priced implementation protect users from price movement
    ///      between their quote and transaction execution. V1 passes the
    ///      maximum uint and therefore preserves its fixed-fee behaviour.
    function _register(address sponsor, address parent, Side side, uint256 maximumPayment) internal {
        if (!configured) revert StagesNotConfigured();
        if (members[msg.sender].active) revert AlreadyRegistered();

        bool isRoot = memberCount == 0;

        // The root position is free and outranks every other node, so it is
        // reserved for the address named at deployment rather than handed to
        // whoever transacts first.
        if (isRoot && msg.sender != designatedRoot) revert NotDesignatedRoot();

        if (!isRoot) {
            if (sponsor == address(0) || !members[sponsor].active) {
                revert SponsorNotRegistered();
            }
        }

        memberCount++;
        members[msg.sender] = Member({
            active: true, sponsor: isRoot ? address(0) : sponsor, joinedAt: uint64(block.timestamp), totalEarned: 0
        });

        emit MemberRegistered(msg.sender, sponsor, memberCount);

        _updateWeeklySponsor(sponsor);

        if (isRoot) {
            _enrollRoot(0);
        } else {
            _joinStage(0, parent, side, maximumPayment);
        }
    }

    /// @notice Enrol a member as a tree root at a stage: no fee, no parent.
    /// @dev NOT restricted to the system root — any registered member who has
    ///      completed the previous stage can be enrolled here, and each stage
    ///      may have several roots, each owning an independent board. This is
    ///      deliberate (it is how a stage is seeded), but it is a real operator
    ///      privilege and should be read as one: the member skips this stage's
    ///      fee entirely and still earns from everyone placed beneath them.
    ///      Hold OPERATOR_ROLE on a key you trust accordingly.
    /// @param member   The member to enrol as a root at this stage
    /// @param stageId  Stage to enroll at (1-5)
    function enrollStageRoot(address member, uint256 stageId) external onlyRole(OPERATOR_ROLE) {
        if (stageId == 0 || stageId >= MAX_STAGES) revert InvalidStage(stageId);
        if (!members[member].active) revert NotRegistered();
        if (stageMemberships[member][stageId].enrolled) {
            revert AlreadyEnrolledInStage(stageId);
        }
        if (!stageMemberships[member][stageId - 1].enrolled) {
            revert PreviousStageRequired(stageId - 1);
        }

        stageMemberships[member][stageId] = StageMembership({
            enrolled: true,
            parent: address(0),
            side: Side.None,
            left: address(0),
            right: address(0),
            slotsFilledBelow: 0,
            rolloverCount: 0,
            lastAwardedRollover: 0,
            stageEarnings: 0,
            totalAwarded: 0
        });

        // First root seeded at this stage becomes its permanent fallback
        // anchor, so `findPlacementSlot` never needs an off-chain hint.
        if (stageAnchor[stageId] == address(0)) {
            stageAnchor[stageId] = member;
            emit StageAnchorSet(stageId, member);
        }

        emit StageJoined(member, stageId, address(0), Side.None, 0);
    }

    /// @notice Join the next stage. Must have completed the previous stage.
    /// @param stageId  Stage to join (1-5)
    /// @param parent   Tree parent at this stage
    /// @param side     Left or Right
    function joinStage(uint256 stageId, address parent, Side side) external virtual nonReentrant whenNotPaused {
        _joinStageEntry(stageId, parent, side, type(uint256).max);
    }

    /// @dev Shared paid-stage entry path; see `_register`.
    function _joinStageEntry(uint256 stageId, address parent, Side side, uint256 maximumPayment) internal {
        if (!configured) revert StagesNotConfigured();
        if (!members[msg.sender].active) revert NotRegistered();
        if (stageId == 0 || stageId >= MAX_STAGES) revert InvalidStage(stageId);
        if (stageMemberships[msg.sender][stageId].enrolled) {
            revert AlreadyEnrolledInStage(stageId);
        }
        if (!stageMemberships[msg.sender][stageId - 1].enrolled) {
            revert PreviousStageRequired(stageId - 1);
        }

        _joinStage(stageId, parent, side, maximumPayment);
    }

    // ──────────────────────────────────────────────────────────────────
    //  Internal: stage joining logic
    // ──────────────────────────────────────────────────────────────────

    function _enrollRoot(uint256 stageId) internal {
        stageMemberships[msg.sender][stageId] = StageMembership({
            enrolled: true,
            parent: address(0),
            side: Side.None,
            left: address(0),
            right: address(0),
            slotsFilledBelow: 0,
            rolloverCount: 0,
            lastAwardedRollover: 0,
            stageEarnings: 0,
            totalAwarded: 0
        });

        // The system root is stage 0's permanent fallback anchor.
        if (stageAnchor[stageId] == address(0)) {
            stageAnchor[stageId] = msg.sender;
            emit StageAnchorSet(stageId, msg.sender);
        }

        emit StageJoined(msg.sender, stageId, address(0), Side.None, 0);
    }

    function _joinStage(uint256 stageId, address parent, Side side, uint256 maximumPayment) internal {
        if (stageClosed[stageId]) revert StageClosed(stageId);
        if (side == Side.None) revert InvalidSide();
        if (!stageMemberships[parent][stageId].enrolled) {
            revert ParentNotInStage(parent, stageId);
        }
        if (cycleGuardEnabled) {
            _verifyCyclePath(parent, stageId);
        }

        StageMembership storage parentMem = stageMemberships[parent][stageId];
        if (side == Side.Left && parentMem.left != address(0)) {
            revert SlotOccupied(parent, side);
        }
        if (side == Side.Right && parentMem.right != address(0)) {
            revert SlotOccupied(parent, side);
        }

        // Resolve the amounts once so derived contracts can price a stage in a
        // different payment asset without changing any tree/accounting logic.
        // V1 returns the configured token amounts unchanged; V2 overrides the
        // hook to convert USD-denominated configuration into RWAAN.
        (uint256 feeAmount, uint256 rewardAmount) = _stagePaymentAmounts(stageId);
        if (feeAmount > maximumPayment) {
            revert PaymentExceedsMaximum(feeAmount, maximumPayment);
        }

        // pull registration fee (rejects fee-on-transfer tokens)
        _pullExact(msg.sender, feeAmount);

        // place in tree
        stageMemberships[msg.sender][stageId] = StageMembership({
            enrolled: true,
            parent: parent,
            side: side,
            left: address(0),
            right: address(0),
            slotsFilledBelow: 0,
            rolloverCount: 0,
            lastAwardedRollover: 0,
            stageEarnings: 0,
            totalAwarded: 0
        });

        if (side == Side.Left) {
            parentMem.left = msg.sender;
        } else {
            parentMem.right = msg.sender;
        }

        emit StageJoined(msg.sender, stageId, parent, side, feeAmount);

        // pay every upline whose board this placement lands on
        uint256 poolPaid = _payUplines(stageId, parent, msg.sender, rewardAmount);

        // whatever the uplines did not consume goes to treasury
        uint256 treasuryAmount = feeAmount - poolPaid;
        pendingTreasury += treasuryAmount;
        totalTreasuryPaid += treasuryAmount;

        // credit the placement to every board it lands on
        _propagateSlotFilled(parent, stageId);
    }

    /// @dev Pricing hook. V1 stores payment-token amounts directly. A derived
    ///      implementation may instead convert stable denomination values into
    ///      the payment asset at transaction time.
    function _stagePaymentAmounts(uint256 stageId)
        internal
        view
        virtual
        returns (uint256 feeAmount, uint256 rewardAmount)
    {
        StageConfig storage config = stages[stageId];
        return (config.fee, config.nodeReward);
    }

    /// @notice Pay every upline whose board this placement lands on.
    /// @dev A board is `treeDepth` levels deep, so the walk is capped at
    ///      `treeDepth` ancestors. Each receives one full `nodeReward`.
    ///      Members near the top of a fresh tree have fewer ancestors and
    ///      therefore cost less than the maximum; the unspent remainder goes
    ///      to treasury. `configureStages` guarantees
    ///      `treeDepth * nodeReward < fee`, so the payout can never exceed
    ///      the fee that funded it.
    /// @return totalPaid Sum actually transferred to uplines.
    function _payUplines(uint256 stageId, address startParent, address fromMember, uint256 reward)
        internal
        returns (uint256 totalPaid)
    {
        StageConfig storage config = stages[stageId];
        uint256 maxLevels = config.treeDepth;

        address current = startParent;
        for (uint256 level = 0; level < maxLevels && current != address(0); level++) {
            StageMembership storage mem = stageMemberships[current][stageId];

            mem.stageEarnings += reward;
            members[current].totalEarned += reward;
            totalPaid += reward;

            asset.safeTransfer(current, reward);
            emit NodeRewardPaid(current, fromMember, stageId, reward);

            // Same rule as the slot walk: a detached branch must not pay
            // uplines it is no longer beneath.
            if (_linkIsStale(current, stageId)) break;
            current = mem.parent;
        }

        totalPoolPaid += totalPaid;
    }

    /// @dev Credits the placement to every board it lands on, capped at
    ///      `treeDepth` levels for the same reason as `_payUplines`: a member
    ///      more than `treeDepth` levels below you is not on your board.
    ///      The cap also bounds gas at a constant regardless of tree shape.
    /// @dev True when `node`'s upward `parent` link is stale — the parent no
    ///      longer points back at it.
    ///
    ///      Rollover clears a board owner's child pointers but leaves the
    ///      children's `parent` intact, so the link becomes one-way. Walking
    ///      through it would credit and pay an ancestor for a placement that is
    ///      no longer anywhere in their tree, which is how a detached branch
    ///      could roll an ancestor whose live board was empty.
    function _linkIsStale(address node, uint256 stageId) internal view returns (bool) {
        address parent = stageMemberships[node][stageId].parent;
        if (parent == address(0)) return false; // a root, not a stale link

        StageMembership storage pm = stageMemberships[parent][stageId];
        return pm.left != node && pm.right != node;
    }

    function _propagateSlotFilled(address node, uint256 stageId) internal {
        StageConfig storage config = stages[stageId];
        uint256 maxLevels = config.treeDepth;
        address current = node;

        for (uint256 level = 0; level < maxLevels && current != address(0); level++) {
            StageMembership storage mem = stageMemberships[current][stageId];
            mem.slotsFilledBelow++;

            if (mem.slotsFilledBelow >= config.treeSlots) {
                mem.rolloverCount++;
                mem.slotsFilledBelow = 0;
                mem.left = address(0);
                mem.right = address(0);

                emit Rollover(current, stageId, mem.rolloverCount);
            }

            // Stop at a detachment rather than walking through it.
            if (_linkIsStale(current, stageId)) break;
            current = mem.parent;
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  Admin: physical awards
    // ──────────────────────────────────────────────────────────────────

    /// @notice Grant a physical/cash award to a member who met the rollover threshold.
    ///         Funds come from treasury balance (must be pre-funded or use pendingTreasury).
    /// @param member   The member receiving the award
    /// @param stageId  The stage they completed
    /// @param amount   Award amount in asset tokens (admin determines this)
    function grantPhysicalAward(address member, uint256 stageId, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
        if (stageId >= MAX_STAGES) revert InvalidStage(stageId);

        StageMembership storage mem = stageMemberships[member][stageId];
        if (!mem.enrolled) revert NotRegistered();

        StageConfig storage config = stages[stageId];
        if (config.rolloversForAward == 0) revert InvalidStage(stageId);

        uint256 nextMilestone = mem.lastAwardedRollover + config.rolloversForAward;
        if (mem.rolloverCount < nextMilestone) {
            revert RolloversNotMet(nextMilestone, mem.rolloverCount);
        }

        uint256 maxTotalAward = (mem.stageEarnings * awardCapBps) / MAX_AWARD_CAP_BPS;
        uint256 available = maxTotalAward > mem.totalAwarded ? maxTotalAward - mem.totalAwarded : 0;
        if (amount > available) revert AwardExceedsCap(available, amount);

        // Awards are paid out of treasury funds, so the liability has to fall
        // with the payment. Without this the contract kept promising treasury
        // money it had already given away: with no pre-seed, a single award
        // left `pendingTreasury` above the actual balance and the treasury
        // could no longer withdraw what the books said it was owed.
        if (amount > pendingTreasury) {
            revert InsufficientPendingTreasury(pendingTreasury, amount);
        }
        pendingTreasury -= amount;
        totalAwardsPaid += amount;

        mem.lastAwardedRollover = nextMilestone;
        mem.totalAwarded += amount;

        uint256 recordIndex = awardRecords.length;
        awardRecords.push(
            AwardRecord({member: member, stageId: stageId, amount: amount, timestamp: uint64(block.timestamp)})
        );

        if (amount > 0) {
            asset.safeTransfer(member, amount);
        }

        emit PhysicalAwardGranted(member, stageId, amount, recordIndex);
    }

    // ──────────────────────────────────────────────────────────────────
    //  Admin: treasury
    // ──────────────────────────────────────────────────────────────────

    /// @notice Add funds to the treasury balance from outside the fee flow.
    /// @dev Awards are now drawn from `pendingTreasury`, so an operator who
    ///      wants to pay awards larger than accumulated fees tops the treasury
    ///      up here rather than transferring tokens straight to the contract.
    ///      A raw transfer would raise the balance without raising the tracked
    ///      liability, leaving funds the accounting cannot see or spend.
    ///      Permissionless on purpose: paying in is never a privileged act.
    function fundTreasury(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidFeeConfig();
        _pullExact(msg.sender, amount);
        pendingTreasury += amount;
        totalTreasuryPaid += amount;
        emit TreasuryFunded(amount);
    }

    function withdrawTreasury(uint256 amount) external virtual nonReentrant whenNotPaused onlyRole(TREASURY_ROLE) {
        if (amount > pendingTreasury) {
            revert InsufficientPendingTreasury(pendingTreasury, amount);
        }
        pendingTreasury -= amount;
        asset.safeTransfer(treasury, amount);
        emit TreasuryWithdrawn(treasury, amount);
    }

    function setTreasury(address newTreasury) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        address old = treasury;
        treasury = newTreasury;
        emit TreasuryAddressUpdated(old, newTreasury);
    }

    // ──────────────────────────────────────────────────────────────────
    //  Admin: runtime configuration
    // ──────────────────────────────────────────────────────────────────

    function updateStageFee(uint256 stageId, uint256 newFee, uint256 newNodeReward)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!configured) revert StagesNotConfigured();
        if (stageId >= MAX_STAGES) revert InvalidStage(stageId);
        if (newFee == 0 || newNodeReward == 0) revert InvalidFeeConfig();

        StageConfig storage config = stages[stageId];
        // Same solvency rule as configureStages: a full-depth placement pays
        // treeDepth uplines, and the fee must still leave something over.
        if (newNodeReward * config.treeDepth >= newFee) revert InvalidFeeConfig();

        emit StageFeeUpdated(stageId, config.fee, newFee, config.nodeReward, newNodeReward);
        config.fee = newFee;
        config.nodeReward = newNodeReward;
    }

    function updateAwardThreshold(uint256 stageId, uint256 newRolloversForAward) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!configured) revert StagesNotConfigured();
        if (stageId >= MAX_STAGES) revert InvalidStage(stageId);

        StageConfig storage config = stages[stageId];
        emit AwardThresholdUpdated(stageId, config.rolloversForAward, newRolloversForAward);
        config.rolloversForAward = newRolloversForAward;
    }

    /// @notice Set the award ceiling as a share of the member's stage earnings.
    /// @dev Hard-capped at 100%. Raising it above that would re-open farming:
    ///      the attack becomes profitable the moment an award can exceed what
    ///      the board actually generated. If larger awards are wanted, raise
    ///      `nodeReward` or `rolloversForAward` instead — both increase genuine
    ///      earnings and the cost of faking them at the same time.
    function setAwardCapBps(uint256 newCapBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newCapBps > MAX_AWARD_CAP_BPS) revert InvalidAwardCap(newCapBps);
        emit AwardCapUpdated(awardCapBps, newCapBps);
        awardCapBps = newCapBps;
    }

    function setCycleGuardEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        cycleGuardEnabled = enabled;
        emit CycleGuardToggled(enabled);
    }

    function setStageOpen(uint256 stageId, bool open) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (stageId >= MAX_STAGES) revert InvalidStage(stageId);
        stageClosed[stageId] = !open;
        emit StageToggled(stageId, open);
    }

    // ──────────────────────────────────────────────────────────────────
    //  Admin: pause
    // ──────────────────────────────────────────────────────────────────

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────────────────────────
    //  Weekly sponsor tracking
    // ──────────────────────────────────────────────────────────────────

    function _updateWeeklySponsor(address sponsor) internal {
        if (sponsor == address(0)) return;

        uint256 week = block.timestamp / 1 weeks;
        if (week != currentWeek) {
            currentWeek = week;
        }

        weeklySponsorCount[week][sponsor]++;
        uint256 count = weeklySponsorCount[week][sponsor];

        if (count > weeklyTopCount[week]) {
            weeklyTopSponsor[week] = sponsor;
            weeklyTopCount[week] = count;
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────────────────────────

    function getStageConfig(uint256 stageId) external view returns (StageConfig memory) {
        if (stageId >= MAX_STAGES) revert InvalidStage(stageId);
        return stages[stageId];
    }

    function getMember(address member) external view returns (Member memory) {
        return members[member];
    }

    function getStageMembership(address member, uint256 stageId) external view returns (StageMembership memory) {
        return stageMemberships[member][stageId];
    }

    function getTreeInfo(address member, uint256 stageId)
        external
        view
        returns (
            address left,
            address right,
            uint256 slotsFilledBelow,
            uint256 rolloverCount,
            uint256 lastAwardedRollover,
            uint256 stageEarnings
        )
    {
        StageMembership storage mem = stageMemberships[member][stageId];
        return
            (mem.left, mem.right, mem.slotsFilledBelow, mem.rolloverCount, mem.lastAwardedRollover, mem.stageEarnings);
    }

    function getAwardInfo(address member, uint256 stageId)
        external
        view
        returns (
            uint256 totalAwarded,
            uint256 lastAwardedRollover,
            uint256 rolloverCount,
            uint256 nextMilestone,
            bool eligible
        )
    {
        StageMembership storage mem = stageMemberships[member][stageId];
        StageConfig storage config = stages[stageId];
        uint256 milestone = mem.lastAwardedRollover + config.rolloversForAward;
        return (
            mem.totalAwarded,
            mem.lastAwardedRollover,
            mem.rolloverCount,
            milestone,
            config.rolloversForAward > 0 && mem.rolloverCount >= milestone
        );
    }

    function getAwardRecordCount() external view returns (uint256) {
        return awardRecords.length;
    }

    function getCurrentWeekSponsorCount(address sponsor) external view returns (uint256) {
        uint256 week = block.timestamp / 1 weeks;
        return weeklySponsorCount[week][sponsor];
    }

    function isSlotAvailable(address parent, uint256 stageId, Side side) external view returns (bool) {
        if (!stageMemberships[parent][stageId].enrolled) return false;
        StageMembership storage mem = stageMemberships[parent][stageId];
        if (side == Side.Left) return mem.left == address(0);
        if (side == Side.Right) return mem.right == address(0);
        return false;
    }

    /// @notice Find the first available slot below a member using BFS.
    /// @return parent  The member with an open slot
    /// @return side    Which side is open (Left preferred)
    function findOpenSlot(address root, uint256 stageId) external view returns (address parent, Side side) {
        return _findOpenSlot(root, stageId);
    }

    /// @notice Sponsor-first placement: walk up the sponsor chain from
    ///         `sponsor` until an enrolled member is found at `stageId`,
    ///         then BFS from them. This is the recommended placement
    ///         strategy — it ensures recruits land on their sponsor's
    ///         board, spreading earnings across active recruiters instead
    ///         of concentrating them at the global root.
    function findSponsorSlot(address sponsor, uint256 stageId) external view returns (address parent, Side side) {
        address current = sponsor;
        for (uint256 i = 0; i < MAX_SPONSOR_WALK && current != address(0); i++) {
            if (stageMemberships[current][stageId].enrolled) {
                return _findOpenSlot(current, stageId);
            }
            current = members[current].sponsor;
        }
        revert SponsorChainExhausted(sponsor, stageId);
    }

    /// @notice **The placement call frontends should use.** Returns a slot that
    ///         is always valid for `register` / `joinStage`, or reverts with a
    ///         reason that is genuinely exceptional.
    ///
    /// @dev `findSponsorSlot` has two failure modes that a caller must
    ///      otherwise handle by hand, and getting either wrong breaks
    ///      placement:
    ///
    ///        1. it reverts `SponsorChainExhausted` when nobody in the sponsor
    ///           chain has reached this stage — the ordinary case at higher
    ///           stages, since members routinely climb before their upline;
    ///        2. it returns `(address(0), Side.None)` when the board it lands
    ///           on is full, and passing that zero to `register` fails with the
    ///           unhelpful `ParentNotInStage(address(0))`.
    ///
    ///      Neither is exceptional in practice, so this function absorbs both:
    ///      it walks the sponsor chain taking the first enrolled ancestor with
    ///      room — preferring to keep a recruit inside their own lineage — and
    ///      falls back to the stage's anchor board only when the whole chain is
    ///      exhausted or full.
    ///
    /// @param sponsor  Who referred this member. May be any registered member.
    /// @param stageId  Stage being joined.
    /// @return parent  A member with a free slot. Never `address(0)`.
    /// @return side    The free side under `parent`.
    function findPlacementSlot(address sponsor, uint256 stageId) external view returns (address parent, Side side) {
        if (stageId >= MAX_STAGES) revert InvalidStage(stageId);

        bool guard = cycleGuardEnabled;

        // 1. Sponsor-first: keep the recruit on their own upline's board.
        address current = sponsor;
        for (uint256 i = 0; i < MAX_SPONSOR_WALK && current != address(0); i++) {
            if (stageMemberships[current][stageId].enrolled) {
                (parent, side) = _findOpenSlot(current, stageId);
                // A slot the guard would reject is not a slot. Skipping it here
                // is what keeps this function's answer usable by `register`.
                (bool live,,) = guard ? _isPlaceable(parent, stageId) : (true, address(0), false);
                if (parent != address(0) && live) {
                    return (parent, side);
                }
                // Board full or not live — continue up the lineage.
            }
            current = members[current].sponsor;
        }

        // 2. Fall back to the stage's anchor board.
        address anchor = stageAnchor[stageId];
        if (anchor == address(0)) revert StageAnchorNotSet(stageId);

        (parent, side) = _findOpenSlot(anchor, stageId);
        if (parent == address(0)) revert NoPlacementAvailable(stageId);
        if (guard) {
            (bool anchorLive,,) = _isPlaceable(parent, stageId);
            if (!anchorLive) revert NoPlacementAvailable(stageId);
        }
    }

    function _findOpenSlot(address root, uint256 stageId) internal view returns (address parent, Side side) {
        if (!stageMemberships[root][stageId].enrolled) {
            revert ParentNotInStage(root, stageId);
        }

        uint256 maxNodes = stages[stageId].treeSlots + 1;
        address[] memory queue = new address[](maxNodes);
        uint256 head = 0;
        uint256 tail = 0;

        queue[tail++] = root;

        while (head < tail) {
            address current = queue[head++];
            StageMembership storage mem = stageMemberships[current][stageId];

            if (mem.left == address(0)) return (current, Side.Left);
            if (mem.right == address(0)) return (current, Side.Right);

            if (tail < maxNodes) {
                queue[tail++] = mem.left;
            }
            if (tail < maxNodes) {
                queue[tail++] = mem.right;
            }
        }

        return (address(0), Side.None);
    }

    // ──────────────────────────────────────────────────────────────────
    //  Internal: cycle guard
    // ──────────────────────────────────────────────────────────────────

    /// @dev Verifies that the proposed parent does not sit beneath an actual
    ///      reciprocal-link cycle and that its live path stays within the
    ///      fixed gas bound. A one-way edge left by an ancestor rollover is a
    ///      valid boundary: the detached subtree becomes an independent board.
    /// @notice Whether `node` may receive a placement under the cycle guard.
    /// @dev The single source of truth for liveness. `_verifyCyclePath` and
    ///      `findPlacementSlot` both defer to this, so the finder can never
    ///      offer a slot that `register` then rejects — previously the finder
    ///      did no liveness check at all and, with the guard enabled, handed
    ///      out slots that reverted for the overwhelming majority of sponsors.
    ///
    ///      Payout and slot propagation remain capped at `treeDepth` and stop
    ///      at the same one-way boundary, so accepting a detached board cannot
    ///      pay or credit its former ancestor.
    /// @return ok       Whether the placement is allowed.
    /// @return offender Reserved for a structurally invalid node.
    /// @return tooDeep  Whether the path was intact but failed to reach a root
    ///                  within `MAX_LIVE_PATH` reciprocal links.
    function _isPlaceable(address node, uint256 stageId)
        internal
        view
        returns (bool ok, address offender, bool tooDeep)
    {
        if (node == address(0)) return (false, node, false);

        address current = node;

        for (uint256 links = 0; links < MAX_LIVE_PATH; links++) {
            address par = stageMemberships[current][stageId].parent;
            if (par == address(0)) return (true, address(0), false);

            StageMembership storage parMem = stageMemberships[par][stageId];
            if (parMem.left != current && parMem.right != current) {
                // Rollover deliberately clears the ancestor's child pointer
                // while retaining the child's historical parent. That stale
                // edge is the root boundary of a new, independently cycling
                // board. Reward and slot propagation stop at this exact edge.
                return (true, address(0), false);
            }
            current = par;
        }

        // The loop verifies exactly MAX_LIVE_PATH edges. Accept a root reached
        // on the final edge; otherwise the path is too deep to validate within
        // the contract's fixed gas bound.
        if (stageMemberships[current][stageId].parent == address(0)) {
            return (true, address(0), false);
        }
        return (false, current, true);
    }

    function _verifyCyclePath(address node, uint256 stageId) internal view {
        (bool ok, address offender, bool tooDeep) = _isPlaceable(node, stageId);
        if (tooDeep) revert ParentPathTooDeep(node, stageId);
        if (!ok) revert ParentOrphanedByCycle(offender, stageId);
    }

    // ──────────────────────────────────────────────────────────────────
    //  Internal: fee-on-transfer guard
    // ──────────────────────────────────────────────────────────────────

    function _pullExact(address from, uint256 amount) internal {
        uint256 balBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(from, address(this), amount);
        uint256 balAfter = asset.balanceOf(address(this));
        if (balAfter - balBefore != amount) revert TransferAmountMismatch();
    }
}
