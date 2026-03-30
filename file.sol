// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SlotMachine is VRFConsumerBaseV2, ReentrancyGuard {
    IERC20 public immutable token;
    VRFCoordinatorV2Interface COORD;
    uint64 s_subscriptionId;
    bytes32 keyHash;
    uint32 callbackGasLimit = 200000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;

    struct Bet { address player; uint256 amount; }
    mapping(uint256 => Bet) public bets;

    // events
    event BetPlaced(uint256 requestId, address player, uint256 amount);
    event SpinResult(uint256 requestId, address player, uint256 amount, uint256 outcome, uint256 payout);

    constructor(
        address _token,
        address vrfCoordinator,
        bytes32 _keyHash,
        uint64 subscriptionId
    ) VRFConsumerBaseV2(vrfCoordinator) {
        token = IERC20(_token);
        COORD = VRFCoordinatorV2Interface(vrfCoordinator);
        keyHash = _keyHash;
        s_subscriptionId = subscriptionId;
    }

    // Player must approve this contract to transfer SDUCK before calling
    function placeBet(uint256 amount) external nonReentrant {
        require(amount > 0, "Bet>0");
        token.transferFrom(msg.sender, address(this), amount);

        uint256 requestId = COORD.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        bets[requestId] = Bet(msg.sender, amount);
        emit BetPlaced(requestId, msg.sender, amount);
    }

    // Chainlink VRF callback
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        Bet memory b = bets[requestId];
        require(b.player != address(0), "No bet");

        uint256 rnd = randomWords[0] % 100; // 0-99
        uint256 payout = 0;

        // Simple odds example:
        // if rnd < 2 -> jackpot 100x
        // else if rnd < 12 -> 10x
        // else if rnd < 37 -> 2x
        // else -> lose
        if (rnd < 2) payout = b.amount * 100;
        else if (rnd < 12) payout = b.amount * 10;
        else if (rnd < 37) payout = b.amount * 2;
        else payout = 0;

        if (payout > 0) {
            // ensure contract has enough tokens
            uint256 bal = token.balanceOf(address(this));
            uint256 pay = payout;
            if (pay > bal) pay = bal; // safe fallback
            token.transfer(b.player, pay);
        }
        emit SpinResult(requestId, b.player, b.amount, rnd, payout);
        delete bets[requestId];
    }

    // Owner functions (add liquidity, withdraw)
    function withdrawTokens(address to, uint256 amount) external {
        // implement access control in production (Ownable)
        token.transfer(to, amount);
    }
}
