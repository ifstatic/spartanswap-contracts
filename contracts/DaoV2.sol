// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;
import "./DaoVault.sol"; 
import "./iBEP20.sol";
import "./iDAO.sol";
import "./iDAOVAULT.sol";
import "./iBASE.sol";
import "./iUTILS.sol";
import "./iROUTER.sol";
import "./iBOND.sol";
import "./iRESERVE.sol";
import "./iSYNTHFACTORY.sol"; 
import "./iPOOLFACTORY.sol";


contract Dao {

    address public DEPLOYER;
    address public BASE;

   
    bool public daoHasMoved;
    address public DAO;

    iUTILS public _UTILS;
    iRESERVE public _RESERVE;

    // Only Deployer can execute
     // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DEPLOYER);
        _;
    }
    constructor (address _base) public {
        BASE = _base;
        DEPLOYER = msg.sender;
        DAO = address(this);
    }
    function setGenesisAddresses(address _utils,address _reserve ) public onlyDAO {
        _UTILS = iUTILS(_utils);
        _RESERVE = iRESERVE(_reserve);
    }
 
    function UTILS() public view returns(iUTILS){
        if(daoHasMoved){
            return Dao(DAO).UTILS();
        } else {
            return _UTILS;
        }
    }
    function RESERVE() public view returns(iRESERVE){
        if(daoHasMoved){
            return Dao(DAO).RESERVE();
        } else {
            return _RESERVE;
        }
    }

}


   