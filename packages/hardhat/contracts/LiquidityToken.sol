// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LiquidityToken
 * @dev Token ERC20 que representa las participaciones de liquidez en el SimpleSwap
 * Solo el contrato SimpleSwap puede mintear y quemar estos tokens
 */
contract LiquidityToken is ERC20, Ownable {
    
    // Dirección del contrato SimpleSwap autorizado
    address public simpleSwapContract;
    
    // Evento para cuando se asigna el contrato SimpleSwap
    event SimpleSwapContractSet(address indexed simpleSwap);

    /**
     * @dev Constructor que establece el nombre y símbolo del token
     */
    constructor() ERC20("LiquidityToken", "LIT") Ownable(msg.sender) {
        // El owner inicial deploy el contrato
    }

    /**
     * @dev Modifier para restringir funciones solo al contrato SimpleSwap
     */
    modifier onlySimpleSwap() {
        require(msg.sender == simpleSwapContract, "LiquidityToken: ONLY_SIMPLE_SWAP");
        _;
    }

    /**
     * @dev Establece la dirección del contrato SimpleSwap autorizado
     * Solo puede ser llamado por el owner y solo una vez
     * @param _simpleSwapContract Dirección del contrato SimpleSwap
     */
    function setSimpleSwapContract(address _simpleSwapContract) external onlyOwner {
        require(_simpleSwapContract != address(0), "LiquidityToken: ZERO_ADDRESS");
        require(simpleSwapContract == address(0), "LiquidityToken: ALREADY_SET");
        
        simpleSwapContract = _simpleSwapContract;
        emit SimpleSwapContractSet(_simpleSwapContract);
    }

    /**
     * @dev Mintea tokens de liquidez - solo puede ser llamado por SimpleSwap
     * @param to Dirección que recibirá los tokens
     * @param amount Cantidad de tokens a mintear
     */
    function mint(address to, uint256 amount) external onlySimpleSwap {
        require(to != address(0), "LiquidityToken: MINT_TO_ZERO_ADDRESS");
        require(amount > 0, "LiquidityToken: MINT_ZERO_AMOUNT");
        
        _mint(to, amount);
    }

    /**
     * @dev Quema tokens de liquidez - solo puede ser llamado por SimpleSwap
     * @param from Dirección de la cual quemar tokens
     * @param amount Cantidad de tokens a quemar
     */
    function burn(address from, uint256 amount) external onlySimpleSwap {
        require(from != address(0), "LiquidityToken: BURN_FROM_ZERO_ADDRESS");
        require(amount > 0, "LiquidityToken: BURN_ZERO_AMOUNT");
        require(balanceOf(from) >= amount, "LiquidityToken: INSUFFICIENT_BALANCE");
        
        _burn(from, amount);
    }

    /**
     * @dev Override para prevenir transferencias accidentales al contrato SimpleSwap
     * Los usuarios pueden transferir libremente sus tokens LP entre ellos
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(to != simpleSwapContract, "LiquidityToken: TRANSFER_TO_SIMPLE_SWAP");
        return super.transfer(to, amount);
    }

    /**
     * @dev Override para prevenir transferencias accidentales al contrato SimpleSwap
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(to != simpleSwapContract, "LiquidityToken: TRANSFER_TO_SIMPLE_SWAP");
        return super.transferFrom(from, to, amount);
    }

    /**
     * @dev Función de conveniencia para obtener balance en formato legible
     * @param account Dirección a consultar
     * @return Balance sin decimales (dividido por 10^18)
     */
    function balanceOfReadable(address account) public view returns (uint256) {
        return balanceOf(account) / 10**decimals();
    }

    /**
     * @dev Función de conveniencia para obtener el total supply en formato legible
     * @return Total supply sin decimales (dividido por 10^18)
     */
    function totalSupplyReadable() public view returns (uint256) {
        return totalSupply() / 10**decimals();
    }
}