// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;
import "./poolV2.sol";

interface iSYNTHFACTORY {
    function isSynth(address) external view returns (bool);

}
interface iPOOLFACTORY {
    function isCuratedPool(address) external view returns (bool);
    function challengLowestCuratedPool(address) external  ;
    function addCuratedPool(address) external ;
    function removeCuratedPool(address) external  ;
    function isPool(address) external view returns (bool);
    function getPool(address) external view returns(address payable);
}
interface iLEND {
    function checkInterest(address) external ;
}

contract Router {
    using SafeMath for uint256;
    address public BASE;
    address private NDAO;
    address public WBNB;
    address public DEPLOYER;
    uint public secondsPerEra;
    uint public nextEraTime;
    uint private maxTrades;
    uint private eraLength;
    uint public normalAverageFee;
    uint private arrayFeeSize;
    uint [] private feeArray;
    uint private lastMonth;

    mapping(address=> uint) public map30DPoolRevenue;
    mapping(address=> uint) public mapPast30DPoolRevenue;

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == _DAO().DAO() || msg.sender == DEPLOYER);
        _;
    }

    constructor (address _base, address _wbnb, address _newDao) public payable {
        NDAO = _newDao;
        BASE = _base;
        WBNB = _wbnb;
        arrayFeeSize = 20;
        eraLength = 30;
        maxTrades = 100;
        lastMonth = 0;
        DEPLOYER = msg.sender;
    }

    function _DAO() internal view returns(iDAO) {
        bool status = iDAO(NDAO).MSTATUS();
        if(status == true){
         return iBASE(BASE).DAO();
        }else{
          return iNDAO(NDAO).DAO();
        }
    }

    receive() external payable {}

    // Add liquidity for self
    function addLiquidity(uint inputBase, uint inputToken, address token) public payable returns (uint units) {
        units = addLiquidityForMember(inputBase, inputToken, token, msg.sender);
        return units;
    }

    // Add liquidity for member
    function addLiquidityForMember(uint inputBase, uint inputToken, address token, address member) public payable returns (uint units) {
        address pool = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(token); 
        _handleTransferIn(BASE, inputBase, pool);
        _handleTransferIn(token, inputToken, pool);
        units = Pool(pool).addLiquidityForMember(member);
        return units;
    }
    function addLiquidityAsym(uint inputToken, bool fromBase, address token) public payable returns (uint units) {
       return addLiquidityAsymForMember(inputToken,fromBase, token, msg.sender);
    }

    function zapLiquidity(uint unitsLP, address fromToken, address toToken) public payable returns (uint units){
        address _poolTo = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(toToken);
        require(iPOOLFACTORY(_DAO().POOLFACTORY()).isPool(_poolTo) == true);
        address _poolFrom = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(fromToken);
        require(iPOOLFACTORY(_DAO().POOLFACTORY()).isPool(_poolFrom) == true);
        address _member = msg.sender; 
        require(unitsLP <= iBEP20(_poolFrom).totalSupply());
        (uint outputBase,) = removeLiquidityAsymForMember(unitsLP, true,  fromToken, address(this));
        iBEP20(BASE).transfer(_poolTo,outputBase);
        units = Pool(_poolTo).addLiquidityForMember(_member);
         Pool(_poolTo).sync();
         return (units);
    }
    // Add Asymmetrically
    function addLiquidityAsymForMember(uint inputToken, bool fromBase, address token, address member) public payable returns (uint units) {
        require(inputToken > 0);
        uint halfInput = inputToken.mul(5000).div(10000);
         address _pool = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(token);
         address _token = token;
        if(token == address(0)){_token = WBNB;} // Handle BNB
        if(fromBase){
             _handleTransferIn(BASE, inputToken, address(this));
             iBEP20(BASE).transfer(_pool,halfInput);
             (uint _tokenBought,uint fee ) = Pool(_pool).swap(_token);
             getsDividend(_pool,token, fee);
             iBEP20(BASE).transfer(_pool,halfInput);
             iBEP20(_token).transfer(_pool,_tokenBought);
             units = Pool(_pool).addLiquidityForMember(member);
        } else {
            _handleTransferIn(token, inputToken, address(this));
             iBEP20(_token).transfer(_pool,halfInput);
            (uint _baseBought, uint fee ) = Pool(_pool).swap(BASE);
            getsDividend(_pool,token, fee);
            iBEP20(_token).transfer(_pool,halfInput);
            iBEP20(BASE).transfer(_pool,_baseBought);
            units = Pool(_pool).addLiquidityForMember(member);
        }
        return units;
    }

    // Remove % for self
    function removeLiquidity(uint basisPoints, address token) public returns (uint outputBase, uint outputToken) {
        require((basisPoints > 0 && basisPoints <= 10000));
        uint _units = iUTILS(_DAO().UTILS()).calcPart(basisPoints, iBEP20(iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(token)).balanceOf(msg.sender));
        return removeLiquidityExact(_units, token);
    }
    // Remove an exact qty of units
    function removeLiquidityExact(uint units, address token) public returns (uint outputBase, uint outputToken) {
        address _pool = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(token);
        require(iPOOLFACTORY(_DAO().POOLFACTORY()).isPool(_pool) == true);
        require(units <= iBEP20(_pool).totalSupply());
        address _member = msg.sender;
        Pool(_pool).transferTo(_pool, units);//RPTAF
        (outputBase, outputToken) = Pool(_pool).removeLiquidity();
        _handleTransferOut(token, outputToken, _member);
        _handleTransferOut(BASE, outputBase, _member);
        return (outputBase, outputToken);
    }

    function removeLiquidityAsym(uint units, bool toBase, address token) public returns (uint outputAmount, uint fee){
        (outputAmount, fee) = removeLiquidityAsymForMember(units, toBase, token, msg.sender);
        return (outputAmount, fee);
    }
    // Remove Asymmetrically
    function removeLiquidityAsymForMember(uint units, bool toBase, address token, address member) public returns (uint outputAmount, uint fee){
        address _pool = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(token);
        require(iPOOLFACTORY(_DAO().POOLFACTORY()).isPool(_pool) == true);
         Pool(_pool).transferTo(_pool, units);//RPTAF
        (uint outputBase, uint outputToken) = Pool(_pool).removeLiquidity();
         address _token = token;
        if(token == address(0)){_token = WBNB;} // Handle BNB
        if(toBase){
             iBEP20(_token).transfer(_pool, outputToken);
             (uint _baseBought,uint _feey) = Pool(_pool).swapTo(BASE, address(this));
             getsDividend(_pool,_token, _feey);
            outputAmount = _baseBought.add(outputBase);
            fee = _feey;
            _handleTransferOut(BASE, outputAmount, member);
        } else {
            iBEP20(BASE).transfer(_pool, outputBase);
            (uint _tokenBought,uint _feez) = Pool(_pool).swapTo(_token, address(this));
             getsDividend(_pool,_token, _feez);
            outputAmount = _tokenBought.add(outputToken);
            fee = _feez;
            _handleTransferOut(token, outputAmount, member);
        } 
        
        return (outputAmount, fee);
    }

    //==================================================================================//
    // Swapping Functions
    function buyTo(uint amount, address token, address member) public returns (uint outputAmount, uint fee) {
        address _token = token;
        if(token == address(0)){_token = WBNB;} // Handle BNB
        address _pool = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(token);
        _handleTransferIn(BASE, amount, _pool);
        (outputAmount, fee) = Pool(_pool).swap(_token);
        _handleTransferOut(token, outputAmount, member);
        getsDividend(_pool,token, fee);
        return (outputAmount, fee);
    }
    function sellTo(uint amount, address token, address member) public payable returns (uint outputAmount, uint fee) {
            address _pool = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(token);
             _handleTransferIn(token, amount, _pool);
            (outputAmount, fee) = Pool(_pool).swapTo(BASE, member);
            getsDividend(_pool,token, fee);
            return (outputAmount, fee);
        //iLEND(_DAO().LEND()).checkInterest(BASE);
    }
    function swap(uint256 inputAmount, address fromToken, address toToken) public payable returns (uint256 outputAmount, uint256 fee) {
        return swapTo(inputAmount, fromToken, toToken, msg.sender);
    }
    function swapTo(uint256 inputAmount, address fromToken, address toToken, address member) public payable returns (uint256 outputAmount, uint256 fee) {
        require(fromToken != toToken);
        if(fromToken == BASE){
                (outputAmount, fee) = buyTo(inputAmount, toToken, member);   
        } else if(toToken == BASE) {
               (outputAmount, fee) = sellTo(inputAmount, fromToken, member); 
        } else {
            address _poolTo = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(toToken);
            (,uint feey) = sellTo(inputAmount, fromToken, _poolTo);
            address _toToken = toToken;
            if(toToken == address(0)){_toToken = WBNB;} 
             (uint _zz, uint _feez) = Pool(_poolTo).swap(_toToken);
            fee = feey.add(_feez);
            getsDividend(_poolTo,toToken, fee);
            outputAmount = _zz; 
            _handleTransferOut(toToken, outputAmount, member);
        }
        return (outputAmount, fee);
    }
    function getsDividend(address _pool, address _token, uint fee) internal {
        if(iPOOLFACTORY(_DAO().POOLFACTORY()).isCuratedPool(_pool) == true){
            addTradeFee(fee);
            addDividend(_token, fee); 
           }
    }
    //==================================================================================//
    // Token Transfer Functions
    function _handleTransferIn(address _token, uint256 _amount, address _pool) internal returns(uint256 actual){
        if(_amount > 0) {
            if(_token == address(0)){
                require((_amount == msg.value));
                payable(WBNB).call{value:_amount}(""); 
                iBEP20(WBNB).transfer(_pool, _amount); 
                actual = _amount;
            } else {
                uint startBal = iBEP20(_token).balanceOf(_pool);
                iBEP20(_token).transferFrom(msg.sender, _pool, _amount); 
                actual = iBEP20(_token).balanceOf(_pool).sub(startBal);
            }
        }
    }
    function _handleTransferOut(address _token, uint256 _amount, address _recipient) internal {
        if(_amount > 0) {
            if (_token == address(0)) {
                iWBNB(WBNB).withdraw(_amount);
                payable(_recipient).call{value:_amount}(""); 
            } else {
                iBEP20(_token).transfer(_recipient, _amount);
            }
        }
    }

    //=================================================================================//
    //Swap Synths
    function swapBaseToSynth(uint inputAmount, address synthIN) public returns (uint outPut){
        return swapBaseToSynthFM(inputAmount,  synthIN,  msg.sender);
    }
    function swapBaseToSynthFM(uint inputAmount, address synthOUT, address member) public returns (uint output){
         require(iSYNTHFACTORY(_DAO().SYNTHFACTORY()).isSynth(synthOUT) == true, "!synth");
         address synthOUTLayer1 = iSYNTH(synthOUT).LayerONE();
         address _poolOUT = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(synthOUTLayer1);
         if(tx.origin == member){
         iBASE(BASE).transferTo(_poolOUT, inputAmount); //RPTAF
         }else{
          iBEP20(BASE).transferFrom(member, _poolOUT, inputAmount); 
         }
         (uint outputSynth, uint fee) = Pool(_poolOUT).swapSynthOUT(synthOUT, member); 
         getsDividend( _poolOUT,  synthOUTLayer1,  fee);
         return outputSynth;
    }
    function swapSynthToBase(uint inputAmount, address synthIN) public returns (uint outPut){
        return swapSynthToBaseFM(inputAmount,  synthIN, msg.sender);
    }
    function swapSynthToBaseFM(uint inputAmount, address synthIN, address member) public returns (uint outPut){
        require(iSYNTHFACTORY(_DAO().SYNTHFACTORY()).isSynth(synthIN) == true, "!synth");
        address synthINLayer1 = iSYNTH(synthIN).LayerONE();
        address _poolIN = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(synthINLayer1);
        if(tx.origin == member){
            iSYNTH(synthIN).transferTo(_poolIN, inputAmount); //RPTAF
        }else{
            iBEP20(synthIN).transferFrom(member, _poolIN, inputAmount); 
        }
        (uint outputBase, uint fee) = Pool(_poolIN).swapSynthIN(synthIN, member); 
        getsDividend(_poolIN, synthINLayer1, fee);
        return outputBase;
    }
    
    //==================================================================================//
    //Token Dividends / Curated Pools
    function addDividend(address _token, uint256 _fees) internal {
        if(!(normalAverageFee == 0)){
             uint reserve = iBEP20(BASE).balanceOf(address(this)); // get base balance
            if(!(reserve == 0)){
            address _pool = iPOOLFACTORY(_DAO().POOLFACTORY()).getPool(_token);
            uint dailyAllocation = reserve.div(eraLength).div(maxTrades); // get max dividend for reserve/30/100 
            uint numerator = _fees.mul(dailyAllocation);
            uint feeDividend = numerator.div(_fees.add(normalAverageFee));
            revenueDetails(feeDividend,_pool);
            iBEP20(BASE).transfer(_pool,feeDividend);   
            Pool(_pool).sync();
            }
        }
       
    }
    function addTradeFee(uint fee) internal {
        uint totalTradeFees = 0;
        uint arrayFeeLength = feeArray.length;
        if(!(arrayFeeLength == arrayFeeSize)){
            feeArray.push(fee);
        }else {
            addFee(fee);
            for(uint i = 0; i<arrayFeeSize; i++){
            totalTradeFees = totalTradeFees.add(feeArray[i]);
        }
        }
        normalAverageFee = totalTradeFees.div(arrayFeeSize); 
    }
    function addFee(uint fee) internal {
        uint n = feeArray.length;//20
        for (uint i = n - 1; i > 0; i--) {
        feeArray[i] = feeArray[i - 1];
        }
         feeArray[0] = fee;
    }
    function revenueDetails(uint fees, address pool) internal {
        if(lastMonth == 0){
            lastMonth = Pool(pool).genesis();
        }
        if(block.timestamp <= lastMonth.add(2592000)){//30days
            map30DPoolRevenue[pool] = map30DPoolRevenue[pool].add(fees);
        }else{
            lastMonth = lastMonth.add(2592000);
            mapPast30DPoolRevenue[pool] = map30DPoolRevenue[pool];
            map30DPoolRevenue[pool] = 0;
            map30DPoolRevenue[pool] = map30DPoolRevenue[pool].add(fees);
        }
        
    }
    //=================================onlyDAO=====================================//
    function changeArrayFeeSize(uint _size) public onlyDAO {
        arrayFeeSize = _size;
    }
    function changeMaxTrades(uint _maxtrades) public onlyDAO {
        maxTrades = _maxtrades;
    }
    function changeEraLength(uint _eraLength) public onlyDAO {	
        eraLength = _eraLength;	
    }
    function forwardRouterFunds(address newRouterAddress ) public onlyDAO {
        uint balanceBase = iBEP20(BASE).balanceOf(address(this)); // get base balance
        iBEP20(BASE).transfer(newRouterAddress, balanceBase);
    }
    function grantFunds(uint amount, address grantee) public onlyDAO returns (bool){
        require(amount < iBEP20(BASE).balanceOf(address(this)));
        require(grantee != address(0));
        iBEP20(BASE).transfer(grantee, amount);
        return true;
    }
    function destroyRouter() public onlyDAO {
         selfdestruct(msg.sender);
    }


}