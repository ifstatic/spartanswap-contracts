// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;
import "./iDAO.sol";
interface iBASE {
    function DAO() external view returns (iDAO);
    function secondsPerEra() external view returns (uint256);
    function changeDAO(address) external returns(bool);
    function setParams(uint256, uint256) external;
    function flipEmissions() external returns(bool);
}