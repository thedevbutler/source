pragma solidity >= 0.8.19;

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;

    function addLiquidityETH(address token, uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function removeLiquidityETH(address token, uint liquidity, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external returns (uint amountToken, uint amountETH);
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

abstract contract Ownable {
    address private owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Caller must be owner");
        _;
    }

    function getOwner() public view returns (address) {
        return owner;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        owner = newOwner;
    }
}

contract DevButlerBlueprint is Ownable, IERC20 {

    IUniswapV2Router02 public constant UNISWAP_ROUTER = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public UNISWAP_PAIR;

    address private constant DEVBUTLER_FEE_RECIPIENT = 0xa55dc4860EE12BAA7dDe8043708B582a4eeBe617;

    uint8 private constant DEVBUTLER_BUYFEE = 10; // = 1 %
    uint8 private constant DEVBUTLER_SELLFEE = 10; // = 1 %
    uint8 private constant FEE_TRANSFER_INTERVAL = 1;
    uint8 private constant FAIR_EXIT_OWNER_REFUND_PERCENTAGE = 101; // = 101 %
    uint16 private constant HOLDER_SHARE_THRESHOLD = 10000;

    string constant private NAME = "Hello";
    string constant private SYMBOL = "HLO";
    uint8 constant private DECIMALS = 8;
    uint256 constant private TOTAL_SUPPLY = 10000000000000 * (10 ** DECIMALS);
    uint256 constant private TEAM_SUPPLY = 5000000000000 * (10 ** DECIMALS);
    uint256 private MAX_TRANSACTION = 10000000000000 * (10 ** DECIMALS);
    uint256 private MAX_WALLET = 10000000000000 * (10 ** DECIMALS);
    address private OWNER_FEE_RECIPIENT = 0x4B0897b0513fdC7C541B6d9D7E929C4e5364D2dB;
    uint8 private OWNER_BUYFEE = 50;
    uint8 private OWNER_SELLFEE = 50;
    bool private AUTO_CASHOUT = true;
    address private constant AFFILIATE_FEE_RECIPIENT = address(0);
    uint8 private constant AFFILIATE_SHARE = 1;

    bool private launched = false;
    bool private ownerLeft = false;
    bool private fairExiting = false;
    bool private feesPaying = false;

    uint256 private initialLiquidityInETH;
    uint256 private initialMintedLiquidityPoolTokens;
    uint256 private ownerFeesAsTokens;
    uint256 private totalOwnerEarnings;
    uint256 private buyTrades;
    uint256 private sellTrades;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private excludedFromFees;
    mapping(address => bool) private excludedFromMaxTransaction;

    event DevButlerDeploy(address deployer);

    constructor() payable {
        address OWNER = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
        
        _balances[address(this)] = TOTAL_SUPPLY - TEAM_SUPPLY;
        emit Transfer(address(0), address(this), _balances[address(this)]);
        if (TEAM_SUPPLY != 0) {
            _balances[OWNER] = TEAM_SUPPLY;
            emit Transfer(address(0), OWNER, _balances[OWNER]);
        }

        UNISWAP_PAIR = IUniswapV2Factory(UNISWAP_ROUTER.factory()).createPair(address(this), UNISWAP_ROUTER.WETH());
        _approve(address(this), address(UNISWAP_ROUTER), type(uint256).max);

        excludedFromFees[DEVBUTLER_FEE_RECIPIENT] = true;
        excludedFromFees[OWNER_FEE_RECIPIENT] = true;
        excludedFromFees[OWNER] = true;
        excludedFromFees[address(0)] = true;
        excludedFromFees[address(this)] = true;
		
        excludedFromMaxTransaction[DEVBUTLER_FEE_RECIPIENT] = true;
        excludedFromMaxTransaction[OWNER_FEE_RECIPIENT] = true;
        excludedFromMaxTransaction[OWNER] = true;
        excludedFromMaxTransaction[address(this)] = true;
        excludedFromMaxTransaction[address(UNISWAP_ROUTER)] = true;
        excludedFromMaxTransaction[UNISWAP_PAIR] = true;
		
        transferOwnership(OWNER);

        emit DevButlerDeploy(msg.sender); // Matches DevButler (0x856d4db9159c940857e5286f14c1fe9caeb7cdbe), otherwise copycat
    }

    receive() external payable {}

    function name() public view virtual returns (string memory) {
        return NAME;
    }

    function symbol() public view virtual returns (string memory) {
        return SYMBOL;
    }

    function decimals() public view virtual returns (uint8) {
        return DECIMALS;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "Approve from the zero address");
        require(spender != address(0), "Approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        require(msg.sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        doTransfer(msg.sender, recipient, amount);
        return true;
    }

	function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
		address spender = msg.sender;
		uint256 currentAllowance = allowance(from, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= value, "ERC20: Insufficient allowance");
            _approve(from, spender, currentAllowance - value);
        }
        doTransfer(from, to, value);
        return true;
    }

    function doTransfer(address sender, address recipient, uint256 amount) internal virtual {
        require(launched, "Token must be launched via DevButler Telegram Bot");

        uint256 totalFees = 0;
        bool takeFees = !fairExiting && !feesPaying && !excludedFromFees[sender] && !excludedFromFees[recipient];
        if (UNISWAP_PAIR == sender) {
            if (!excludedFromMaxTransaction[recipient]) {
                require(amount <= MAX_TRANSACTION, "Buy transfer amount exceeds MAX TX");
                require(amount + _balances[recipient] <= MAX_WALLET, "Buy transfer amount exceeds MAX WALLET");
                buyTrades = buyTrades + 1;
            }
            if (takeFees) {
                totalFees = (OWNER_BUYFEE * amount) / 1000;
                ownerFeesAsTokens = ownerFeesAsTokens + totalFees;
                totalFees = totalFees + ((DEVBUTLER_BUYFEE * amount) / 1000);
            }
        } else if (UNISWAP_PAIR == recipient) {
            if (!excludedFromMaxTransaction[sender]) {
                require(amount <= MAX_TRANSACTION, "Sell transfer amount exceeds MAX TX");
                sellTrades = sellTrades + 1;
                if (sellTrades % FEE_TRANSFER_INTERVAL == 0) {
                    cashout(!AUTO_CASHOUT);
                }
            }
            if (takeFees) {
                totalFees = (OWNER_SELLFEE * amount) / 1000;
                ownerFeesAsTokens = ownerFeesAsTokens + totalFees;
                totalFees = totalFees + ((DEVBUTLER_SELLFEE * amount) / 1000);
            }
        }

        require(_balances[sender] >= amount, "Integer Underflow Protection");

        if (totalFees != 0) {
            amount = amount - totalFees;
            _balances[sender] = _balances[sender] - totalFees;
            _balances[address(this)] = _balances[address(this)] + totalFees;
            emit Transfer(sender, address(this), totalFees);
        }

        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;

        emit Transfer(sender, recipient, amount);

        if (!fairExiting && !ownerLeft && IERC20(UNISWAP_PAIR).balanceOf(address(this)) < initialMintedLiquidityPoolTokens) {
            revert("You cannot decrease liquidity. Call fairExit() to get funds back");
        }

    }

    function manualCashout() external onlyOwner {
        cashout(false);
    }

    function cashout(bool onlyDevButler) internal {
        if (!feesPaying) {
            feesPaying = true;
            uint256 tokensToSwap;
            if (onlyDevButler) {
                if (_balances[address(this)] > ownerFeesAsTokens) {
                    tokensToSwap = _balances[address(this)] - ownerFeesAsTokens;
                }
            } else {
                tokensToSwap = _balances[address(this)];
            }
            if (tokensToSwap != 0) {
                address[] memory path = new address[](2);
                path[0] = address(this);
                path[1] = UNISWAP_ROUTER.WETH();
                try UNISWAP_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    tokensToSwap,
                    0,
                    path,
                    address(this),
                    block.timestamp) {
                        if (address(this).balance != 0) {
                            if (onlyDevButler) {
                                payable(DEVBUTLER_FEE_RECIPIENT).transfer(address(this).balance);
                            } else {
                                uint256 ownerETHShare = ownerFeesAsTokens == 0 ? 0 : calculateETHShare(ownerFeesAsTokens, tokensToSwap, address(this).balance);
                                uint256 devButlerETHShare = address(this).balance - ownerETHShare;
                                if (devButlerETHShare != 0) {
                                    cashoutTeamFees(devButlerETHShare);
                                }
                                if (ownerETHShare != 0) {
                                    totalOwnerEarnings = totalOwnerEarnings + ownerETHShare;
                                    ownerFeesAsTokens = 0;
                                    payable(OWNER_FEE_RECIPIENT).transfer(ownerETHShare);
                                }                   
                            }
                        }      
                    } catch {}
            }
            feesPaying = false;
        }
    }

    function cashoutTeamFees(uint256 ethToTransfer) internal {
        if (AFFILIATE_FEE_RECIPIENT == address(0)) {
            payable(DEVBUTLER_FEE_RECIPIENT).transfer(ethToTransfer);
        } else {
            uint256 affiliateShare = (ethToTransfer * AFFILIATE_SHARE) / 10;
            if (affiliateShare != 0) {
                payable(AFFILIATE_FEE_RECIPIENT).transfer(affiliateShare);
            }
            payable(DEVBUTLER_FEE_RECIPIENT).transfer(ethToTransfer - affiliateShare);
        }
    }
    
    function getStatistics() public view virtual returns (uint256, uint256, uint256, uint256, uint256, uint256, address, uint8, uint8, bool) {
        return (ownerFeesAsTokens, totalOwnerEarnings, sellTrades, buyTrades, 
        MAX_TRANSACTION, MAX_WALLET, OWNER_FEE_RECIPIENT, (OWNER_BUYFEE / 10), (OWNER_SELLFEE / 10), AUTO_CASHOUT);
    }

    function setFeeRecipient(address val) external onlyOwner {
        require(val != address(this), "Invalid address");
        OWNER_FEE_RECIPIENT = val;
    }

    function setCashoutMode(bool val) external onlyOwner {
        AUTO_CASHOUT = val;
    }

    function setMaxTransaction(uint256 val) external onlyOwner {
        require(val >= (TOTAL_SUPPLY / 100), "Max Tx cannot be less than 1% of total supply");
        MAX_TRANSACTION = val;
    }

    function setMaxWallet(uint256 val) external onlyOwner {
        require(val >= (TOTAL_SUPPLY / 100), "Max Wallet cannot be less than 1% of total supply");
        MAX_WALLET = val;
    }

    function setBuyFee(uint8 newBuyFee) public onlyOwner {
        require(newBuyFee <= 20, "Buy Fee cannot be more than 20%");
        OWNER_BUYFEE = newBuyFee * 10;
    }

    function setSellFee(uint8 newSellFee) public onlyOwner {
        require(newSellFee <= 20, "Sell Fee cannot be more than 20%");
        OWNER_SELLFEE = newSellFee * 10;
    }

    function calculateETHShare(uint256 holderBalance, uint256 totalBalance, uint256 remainingETH) internal pure returns (uint256) {
        return ((remainingETH * holderBalance * HOLDER_SHARE_THRESHOLD) / totalBalance) / HOLDER_SHARE_THRESHOLD;
    }

    function addLiquidity() internal onlyOwner {
        (, uint256 amountETH, uint256 liquidity) = UNISWAP_ROUTER.addLiquidityETH{value: msg.value}(
            address(this),
            _balances[address(this)],
            0,
            0,
            address(this),
            block.timestamp
        );
        initialLiquidityInETH = initialLiquidityInETH + amountETH;
        initialMintedLiquidityPoolTokens = initialMintedLiquidityPoolTokens + liquidity;
    }

    function openTrading() external onlyOwner payable {
        require(!launched, "Already launched");
        launched = true;
        addLiquidity();
    }

    function increaseLiquidity() external onlyOwner payable {
        addLiquidity();
    }

    function fairExit() external onlyOwner {
        require(launched, "Not even launched");
        require(!fairExiting, "Already exiting");
        fairExiting = true;
        cashout(false);
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(UNISWAP_PAIR).getReserves();
        uint256 lpTokensToRemove = calculateETHShare((FAIR_EXIT_OWNER_REFUND_PERCENTAGE * initialLiquidityInETH / 100), 
            (IUniswapV2Pair(UNISWAP_PAIR).token0() == address(this) ? reserve1 : reserve0), initialMintedLiquidityPoolTokens);
        IERC20(UNISWAP_PAIR).approve(address(UNISWAP_ROUTER), type(uint256).max);
        UNISWAP_ROUTER.removeLiquidityETH(
            address(this),
            lpTokensToRemove > initialMintedLiquidityPoolTokens ? initialMintedLiquidityPoolTokens : lpTokensToRemove,
            0,
            0,
            address(this),
            block.timestamp
        );
        setBuyFee(0);
        setSellFee(0);
		try IERC20(address(this)).transfer(0x000000000000000000000000000000000000dEaD, _balances[address(this)]) {} catch {}
        try IERC20(UNISWAP_PAIR).transfer(0x000000000000000000000000000000000000dEaD, IERC20(UNISWAP_PAIR).balanceOf(address(this))) {} catch {}
        payable(getOwner()).transfer(address(this).balance);
        transferOwnership(address(0));
        fairExiting = false;
        ownerLeft = true;
    }

}