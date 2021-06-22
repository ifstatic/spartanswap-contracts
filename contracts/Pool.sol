// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;
import "./iBEP20.sol";
import "./iUTILS.sol";
import "./iDAO.sol";
import "./iBASE.sol";
import "./iDAOVAULT.sol";
import "./iROUTER.sol";
import "./iSYNTH.sol"; 
import "./iSYNTHFACTORY.sol"; 
import "./iBEP677.sol"; 
import "hardhat/console.sol";

contract Pool is iBEP20 {  

    address public BASE;
    address public TOKEN;
    address public DEPLOYER;

    string _name; string _symbol;
    uint8 public override decimals; uint256 public override totalSupply;
    mapping(address => uint) private _balances;
    mapping(address => mapping(address => uint)) private _allowances;

    uint256 public baseAmount;
    uint256 public tokenAmount;

    uint private lastMonth;
    uint public genesis;

    uint256 public map30DPoolRevenue;
    uint256 public mapPast30DPoolRevenue;
    uint256 [] public revenueArray;

    //EVENTS
    event AddLiquidity(address indexed member, uint inputBase, uint inputToken, uint unitsIssued);
    event RemoveLiquidity(address indexed member, uint outputBase, uint outputToken, uint unitsClaimed);
    event Swapped(address indexed tokenFrom, address indexed tokenTo,address indexed recipient, uint inputAmount, uint outputAmount, uint fee);
    event MintSynth( address indexed member, uint256 synthMinted,address indexed synth);
    event BurnSynth(address indexed member, uint256 synthBurnt, address indexed synth);

    function _DAO() internal view returns(iDAO) {
         return iBASE(BASE).DAO();
    }
    modifier onlyRouter() {
        require(msg.sender == _DAO().ROUTER());
        _;
    }

    constructor (address _base, address _token) {
        BASE = _base;
        TOKEN = _token;
        string memory poolName = "-SpartanProtocolPool";
        string memory poolSymbol = "-SPP";
        _name = string(abi.encodePacked(iBEP20(_token).name(),poolName));
        _symbol = string(abi.encodePacked(iBEP20(_token).symbol(), poolSymbol));
        decimals = 18;
        genesis = block.timestamp;
        DEPLOYER = msg.sender;
    }


     //========================================iBEP20=========================================//
    function name() public view override returns (string memory) {
        return _name;
    }
    function symbol() public view override returns (string memory) {
        return _symbol;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender]+(addedValue));
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "allowance err");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }
    function _approve( address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "sender");
        require(spender != address(0), "spender");
        if (_allowances[owner][spender] < type(uint256).max) { // No need to re-approve if already max
            _allowances[owner][spender] = amount;
            emit Approval(owner, spender, amount);
        }
    }
    function transferFrom(address sender, address recipient, uint256 amount) external virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        // Unlimited approval (saves an SSTORE)
        if (_allowances[sender][msg.sender] < type(uint256).max) {
            uint256 currentAllowance = _allowances[sender][msg.sender];
            require(currentAllowance >= amount, "allowance err");
            _approve(sender, msg.sender, currentAllowance - amount);
        }
        return true;
    }

    //iBEP677 approveAndCall
    function approveAndCall(address recipient, uint amount, bytes calldata data) external returns (bool) {
      _approve(msg.sender, recipient, type(uint256).max); // Give recipient max approval
      iBEP677(recipient).onTokenApproval(address(this), amount, msg.sender, data); // Amount is passed thru to recipient
      return true;
    }

    //iBEP677 transferAndCall
    function transferAndCall(address recipient, uint amount, bytes calldata data) external returns (bool) {
      _transfer(msg.sender, recipient, amount);
      iBEP677(recipient).onTokenTransfer(address(this), amount, msg.sender, data); // Amount is passed thru to recipient 
      return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "transfer err");
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "balance err");
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "address err");
        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
    function burn(uint256 amount) public virtual override {
        _burn(msg.sender, amount);
    }
    function burnFrom(address account, uint256 amount) public virtual {  
        uint256 decreasedAllowance = allowance(account, msg.sender) - (amount);
        _approve(account, msg.sender, decreasedAllowance); 
        _burn(account, amount);
    }
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "address err");
        require(_balances[account] >= amount, "balance err");
        _balances[account] -= amount;
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    //====================================POOL FUNCTIONS =================================//
    //ADD
    function add() external returns(uint liquidityUnits){
        liquidityUnits = addForMember(msg.sender);
        return liquidityUnits;
    }

    //ADD for member
    function addForMember(address member) public returns (uint liquidityUnits){
        uint256 _actualInputBase = _getAddedBaseAmount();
        uint256 _actualInputToken = _getAddedTokenAmount();
        liquidityUnits = iUTILS(_DAO().UTILS()).calcLiquidityUnits(_actualInputBase, baseAmount, _actualInputToken, tokenAmount, totalSupply);
        _incrementPoolBalances(_actualInputBase, _actualInputToken);
        _mint(member, liquidityUnits); 
        emit AddLiquidity(member, _actualInputBase, _actualInputToken, liquidityUnits);
        return liquidityUnits;
    }
    
    //REMOVE 
    function remove() external returns (uint outputBase, uint outputToken) {
        return removeForMember(msg.sender);
    } 

    //REMOVE for member
    function removeForMember(address member) public returns (uint outputBase, uint outputToken) {
        uint256 _actualInputUnits = balanceOf(address(this));
        outputBase = iUTILS(_DAO().UTILS()).calcLiquidityHoldings(_actualInputUnits, BASE, address(this));
        outputToken = iUTILS(_DAO().UTILS()).calcLiquidityHoldings(_actualInputUnits, TOKEN, address(this));
        _decrementPoolBalances(outputBase, outputToken);
        _burn(address(this), _actualInputUnits);
        iBEP20(BASE).transfer(member, outputBase); 
        iBEP20(TOKEN).transfer(member, outputToken);
        emit RemoveLiquidity(member, outputBase, outputToken, _actualInputUnits);
        return (outputBase, outputToken);
    }

    //SWAP
    function swap(address token) external returns (uint outputAmount, uint fee){
        (outputAmount, fee) = swapTo(token, msg.sender);
        return (outputAmount, fee);
    }
    //SWAPTO
    function swapTo(address token, address member) public payable  returns (uint outputAmount, uint fee) {
        require((token == BASE || token == TOKEN), "Must be BASE or TOKEN");
        address _fromToken; uint _amount;
        if(token == BASE){
            _fromToken = TOKEN;
            _amount = _getAddedTokenAmount();
            (outputAmount, fee) = _swapTokenToBase(_amount);
        } else {
            _fromToken = BASE;
            _amount = _getAddedBaseAmount();
            (outputAmount, fee) = _swapBaseToToken(_amount);
        }
        emit Swapped(_fromToken, token,member, _amount, outputAmount, fee);
        iBEP20(token).transfer(member, outputAmount);
        return (outputAmount, fee);
    }

    //MINTTOKENSYNTH
    function mintTokenSynth(bool fromBASE, address member) external returns(uint output, uint fee) {
        address synthOut = iSYNTHFACTORY(_DAO().SYNTHFACTORY()).getSynth(TOKEN);
        uint _liquidityUnits; uint256 _actualInput;
        require(iSYNTHFACTORY(_DAO().SYNTHFACTORY()).isSynth(synthOut) == true, "!synth");
        if(fromBASE){
             _actualInput = _getAddedBaseAmount();
             output = iUTILS(_DAO().UTILS()).calcSwapOutput(_actualInput, baseAmount, tokenAmount); 
             _liquidityUnits = iUTILS(_DAO().UTILS()).calcLiquidityUnitsAsym(_actualInput, BASE, address(this));
            _incrementPoolBalances(_actualInput, 0);
            uint _fee = iUTILS(_DAO().UTILS()).calcSwapFee(_actualInput, baseAmount, tokenAmount);
            fee = iUTILS(_DAO().UTILS()).calcSpotValueInBase(TOKEN,_fee );
        }else{
            _actualInput = _getAddedTokenAmount();
             output = iUTILS(_DAO().UTILS()).calcSwapOutput(_actualInput, tokenAmount, tokenAmount); 
             _liquidityUnits = iUTILS(_DAO().UTILS()).calcLiquidityUnitsAsym(_actualInput, TOKEN, address(this)); 
            _incrementPoolBalances(0, _actualInput);
            uint _fee = iUTILS(_DAO().UTILS()).calcSwapFee(_actualInput, tokenAmount, tokenAmount);
            fee = iUTILS(_DAO().UTILS()).calcSpotValueInBase(TOKEN,_fee );
        }
        _mint(synthOut, _liquidityUnits); 
        iSYNTH(synthOut).mintSynth(member, output); //mintSynth to member  
        _addPoolMetrics(fee);
        emit MintSynth(member, output, synthOut); // Mint Synth Event
      return (output, fee);
    }

    //MINTBASESYNTH
    function mintBaseSynth(bool fromBASE, address member) external returns(uint output, uint fee) {
       address synthOut = iSYNTHFACTORY(_DAO().SYNTHFACTORY()).getSynth(BASE);
        uint _liquidityUnits; uint256 _actualInput;
        require(iSYNTHFACTORY(_DAO().SYNTHFACTORY()).isSynth(synthOut) == true, "!synth");
        if(fromBASE){
             _actualInput = _getAddedBaseAmount();
             output = iUTILS(_DAO().UTILS()).calcSwapOutput(_actualInput, baseAmount, baseAmount);
             _liquidityUnits = iUTILS(_DAO().UTILS()).calcLiquidityUnitsAsym(_actualInput,BASE, address(this));
            _incrementPoolBalances(_actualInput, 0);
            fee = iUTILS(_DAO().UTILS()).calcSwapFee(_actualInput, baseAmount, baseAmount);
        }else{
            _actualInput = _getAddedTokenAmount();
             output = iUTILS(_DAO().UTILS()).calcSwapOutput(_actualInput, tokenAmount, baseAmount); 
             _liquidityUnits = iUTILS(_DAO().UTILS()).calcLiquidityUnitsAsym(_actualInput, TOKEN, address(this));
            _incrementPoolBalances(0, _actualInput);
            fee = iUTILS(_DAO().UTILS()).calcSwapFee(_actualInput, tokenAmount, baseAmount);
        }
        _mint(synthOut, _liquidityUnits); 
        iSYNTH(synthOut).mintSynth(member, output); //mintSynth to member  
        _addPoolMetrics(fee);
        emit MintSynth(member, output, synthOut); // Mint Synth Event
      return (output, fee);
    }
   
    //BURNSYNTH
    function burnBaseSynth(bool toBase, address member) external returns(uint output, uint fee) {
        address synthIn = iSYNTHFACTORY(_DAO().SYNTHFACTORY()).getSynth(BASE);
       require(iSYNTHFACTORY(_DAO().SYNTHFACTORY()).isSynth(synthIn) == true, "!synth");
       uint _actualInputSynth = iBEP20(synthIn).balanceOf(address(this));
       iBEP20(synthIn).transfer(synthIn, _actualInputSynth);
       iSYNTH(synthIn).burnSynth(); //redeem Synth
       if(toBase){
            output = iUTILS(_DAO().UTILS()).calcSwapOutput(_actualInputSynth, baseAmount, baseAmount);
             fee = iUTILS(_DAO().UTILS()).calcSwapFee(_actualInputSynth, baseAmount, baseAmount);
             _decrementPoolBalances(output, 0);
             iBEP20(BASE).transfer(member, output);
       }else{
            output = iUTILS(_DAO().UTILS()).calcSwapOutput(_actualInputSynth, baseAmount, tokenAmount); 
             uint _fee = iUTILS(_DAO().UTILS()).calcSwapFee(_actualInputSynth, baseAmount, tokenAmount);
            fee = iUTILS(_DAO().UTILS()).calcSpotValueInBase(TOKEN,_fee);
            _decrementPoolBalances(0, output);
            iBEP20(TOKEN).transfer(member, output);
       }
        _addPoolMetrics(fee);
        emit BurnSynth(member, _actualInputSynth, synthIn); // Burn Synth Event
      return (output, fee);
    }

     //BURNSYNTH
    function burnTokenSynth(bool toBase, address member) external returns(uint output, uint fee) {
        address synthIn = iSYNTHFACTORY(_DAO().SYNTHFACTORY()).getSynth(TOKEN);
       require(iSYNTHFACTORY(_DAO().SYNTHFACTORY()).isSynth(synthIn) == true, "!synth");
       uint _actualInputSynth = iBEP20(synthIn).balanceOf(address(this));
       iBEP20(synthIn).transfer(synthIn, _actualInputSynth);
       iSYNTH(synthIn).burnSynth(); //redeem Synth
       if(toBase){
            output = iUTILS(_DAO().UTILS()).calcSwapOutput(_actualInputSynth, tokenAmount, baseAmount);
             fee = iUTILS(_DAO().UTILS()).calcSwapFee(_actualInputSynth, tokenAmount, baseAmount);
             _decrementPoolBalances(output, 0);
             iBEP20(BASE).transfer(member, output);
       }else{
            output = iUTILS(_DAO().UTILS()).calcSwapOutput(_actualInputSynth, tokenAmount, tokenAmount); 
             uint _fee = iUTILS(_DAO().UTILS()).calcSwapFee(_actualInputSynth, tokenAmount, tokenAmount);
            fee = iUTILS(_DAO().UTILS()).calcSpotValueInBase(TOKEN,_fee);
            _decrementPoolBalances(0, output);
            iBEP20(TOKEN).transfer(member, output);
       }
        _addPoolMetrics(fee);
        emit BurnSynth(member, _actualInputSynth, synthIn); // Burn Synth Event
      return (output, fee);
    }

    //=======================================INTERNAL MATHS======================================//
    function _getAddedBaseAmount() internal view returns(uint256 _actual){
        uint _baseBalance = iBEP20(BASE).balanceOf(address(this)); 
        if(_baseBalance > baseAmount){
            _actual = _baseBalance-(baseAmount);
        } else {
            _actual = 0;
        }
        return _actual;
    }
  
    function _getAddedTokenAmount() internal view returns(uint256 _actual){
        uint _tokenBalance = iBEP20(TOKEN).balanceOf(address(this)); 
        if(_tokenBalance > tokenAmount){
            _actual = _tokenBalance-(tokenAmount);
        } else {
            _actual = 0;
        }
        return _actual;
    }

    function _swapBaseToToken(uint256 _x) internal returns (uint256 _y, uint256 _fee){
        uint256 _X = baseAmount;
        uint256 _Y = tokenAmount;
        _y =  iUTILS(_DAO().UTILS()).calcSwapOutput(_x, _X, _Y);
        uint fee = iUTILS(_DAO().UTILS()).calcSwapFee(_x, _X, _Y);
        _fee = iUTILS(_DAO().UTILS()).calcSpotValueInBase(TOKEN, fee);
        _setPoolAmounts(_X + _x, _Y - _y);
        _addPoolMetrics(_fee);
        return (_y, _fee);
    }

    function _swapTokenToBase(uint256 _x) internal returns (uint256 _y, uint256 _fee){
        uint256 _X = tokenAmount;
        uint256 _Y = baseAmount;
        _y =  iUTILS(_DAO().UTILS()).calcSwapOutput(_x, _X, _Y);
        _fee = iUTILS(_DAO().UTILS()).calcSwapFee(_x, _X, _Y);
        _setPoolAmounts(_Y - _y, _X + _x);
        _addPoolMetrics(_fee);
        return (_y, _fee);
    }

    //=======================================BALANCES=========================================//
    // Sync internal balances to actual
    function sync() public {
        baseAmount = iBEP20(BASE).balanceOf(address(this));
        tokenAmount = iBEP20(TOKEN).balanceOf(address(this));
    }
    // Increment internal balances
    function _incrementPoolBalances(uint _baseAmount, uint _tokenAmount) internal  {
        baseAmount += _baseAmount;
        tokenAmount += _tokenAmount;
    }
    // Set internal balances
    function _setPoolAmounts(uint256 _baseAmount, uint256 _tokenAmount) internal  {
        baseAmount = _baseAmount;
        tokenAmount = _tokenAmount; 
    }
    // Decrement internal balances
    function _decrementPoolBalances(uint _baseAmount, uint _tokenAmount) internal  {
        baseAmount -= _baseAmount;
        tokenAmount -= _tokenAmount; 
    }


    //===========================================POOL FEE ROI=================================//
    function _addPoolMetrics(uint256 _fee) internal {
        if(lastMonth == 0){
            lastMonth = genesis;
        }
        if(block.timestamp <= lastMonth+(2592000)){//30Days
            map30DPoolRevenue = map30DPoolRevenue+(_fee);
        }else{
            lastMonth = lastMonth+(2592000);
            mapPast30DPoolRevenue = map30DPoolRevenue;
            addRevenue(mapPast30DPoolRevenue);
            map30DPoolRevenue = 0;
            map30DPoolRevenue = map30DPoolRevenue+(_fee);
        }
    }
    function addRevenue(uint _totalRev) internal {
        if(!(revenueArray.length == 2)){
            revenueArray.push(_totalRev);
        }else {
            addFee(_totalRev);
        }
    }
    function addFee(uint _rev) internal {
        uint _n = revenueArray.length;//2
        for (uint i = _n - 1; i > 0; i--) {
        revenueArray[i] = revenueArray[i - 1];
        }
         revenueArray[0] = _rev;
    }

    

}
