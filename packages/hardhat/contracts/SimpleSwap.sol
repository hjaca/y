// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

/**
 * @title SimpleSwap.sol
 * @dev A smart contract called SimpleSwap that allows you to add and remove liquidity, exchange tokens, obtain prices and 
 *  calculate amounts to receive, replicating the functionality of Uniswap without depending on its protocol.
 *  Kipu Eth course TP3 - Hugo Jaca
 * Functions:
 *      Constructor. Inicializa la subasta con los parámetros necesario para su funcionamiento.
 *      Función para ofertar: Permite a los participantes ofertar por el artículo. Para que una oferta sea válida debe ser mayor que la mayor oferta actual al menos en 5% y debe realizarse mientras la subasta esté activa.
 *      Mostrar ganador: Muestra el ofertante ganador y el valor de la oferta ganadora.
 *      Mostrar ofertas: Muestra la lista de ofertantes y los montos ofrecidos.
 *      Devolver depósitos: Al finalizar la subasta se devuelve el depósito a los ofertantes que no ganaron, descontando una comisión del 2% para el gas.
 * Manejo de depósitos:
 *      Las ofertas se depositan en el contrato y se almacenan con las direcciones de los ofertantes.
 * Eventos:
 *      Nueva Oferta: Se emite cuando se realiza una nueva oferta.
 *      Subasta Finalizada: Se emite cuando finaliza la subasta.
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SimpleSwap is Ownable {
    /// @notice Token A in the liquidity pool
    IERC20 public tokenA;

    /// @notice Token B in the liquidity pool
    IERC20 public tokenB;

    /// @notice Emitted when liquidity is added
    /// @param amountA The amount of token A added
    /// @param amountB The amount of token B added
    event LiquidityAdded(uint256 amountA, uint256 amountB);
    
    /// @notice Emitted when liquidity is removed
    /// @param amountA The amount of token A removed
    /// @param amountB The amount of token B removed
    event LiquidityRemoved(uint256 amountA, uint256 amountB);

    /// @notice Emitted when a token swap occurs
    /// @param user The address of the user performing the swap
    /// @param amountIn The input token amount
    /// @param amountOut The output token amount
    event TokenSwapped(address indexed user, uint256 amountIn, uint256 amountOut);


// 1️⃣Agregar Liquidez (addLiquidity)
// Description: Function for users to add liquidity to a token pair in an ERC-20 pool.
// Interface: function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity);
// Tasks:
// Transfer tokens from the user to the contract.
// Calculate and allocate liquidity based on reserves.
// Issue liquidity tokens to the user.
// Parameters:
// tokenA, tokenB: Token addresses.
// amountADesired, amountBDesired: Desired token amounts.
// amountAMin, amountBMin: Minimum acceptable amounts to avoid failures.
// to: Recipient address.
// deadline: Timestamp for the transaction.
// Returns:
// amountA, amountB, liquidity: Actual amounts and issued liquidity.

    function addLiquidity(uint256 amountA, uint256 amountB) external onlyOwner {
        require(amountA > 0 && amountB > 0, "Amounts must be > 0");
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);

        emit LiquidityAdded(amountA, amountB);
    }

// 2️⃣Remover Liquidez (removeLiquidity)
// Descripción: Función para que los usuarios retiren liquidez de un pool ERC-20.
// Interfaz: function removeLiquidity(address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB);
// Tareas:
// Quemar tokens de liquidez del usuario.
// Calcular y retornar tokens A y B.
// Parámetros:
// tokenA, tokenB: Direcciones de los tokens.
// liquidity: Cantidad de tokens de liquidez a retirar.
// amountAMin, amountBMin: Mínimos aceptables para evitar fallos.
// to: Dirección del destinatario.
// deadline: Marca de tiempo para la transacción.
// Retornos:
// amountA, amountB: Cantidades recibidas tras retirar liquidez.
    function removeLiquidity(uint256 amountA, uint256 amountB) external onlyOwner {
        require(amountA <= tokenA.balanceOf(address(this)) && amountB <= tokenB.balanceOf(address(this)), "Low liquidity");

        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);

        emit LiquidityRemoved(amountA, amountB);
    }

// 3️⃣Intercambiar Tokens (swapExactTokensForTokens)
// Descripción: Función para intercambiar un token por otro en cantidad exacta.
// Interfaz: function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
// Tareas:
// Transferir token de entrada del usuario al contrato.
// Calcular intercambio según reservas.
// Transferir token de salida al usuario.
// Parámetros:
// amountIn: Cantidad de tokens de entrada.
// amountOutMin: Mínimo aceptable de tokens de salida.
// path: Array de direcciones de tokens. (token entrada, token salida)
// to: Dirección del destinatario.
// deadline: Marca de tiempo para la transacción.
// Retornos:
// amounts: Array con cantidades de entrada y salida.

    function swapExactTokensForTokens(uint256 amountAIn) external {
        require(amountAIn > 0, "Amount must be > 0");

        uint256 amountBOut = getAmountOut(amountAIn, tokenA.balanceOf(address(this)), tokenB.balanceOf(address(this)));

        tokenA.transferFrom(msg.sender, address(this), amountAIn);
        tokenB.transfer(msg.sender, amountBOut);

        emit TokenSwapped(msg.sender, amountAIn, amountBOut);
    }

// 4️⃣Obtener el Precio (getPrice)
// Descripción: Función para obtener el precio de un token en términos de otro.
// Interfaz: function getPrice(address tokenA, address tokenB) external view returns (uint price);
// Tareas:
// Obtener reservas de ambos tokens.
// Calcular y retornar el precio.
// Parámetros:
// tokenA, tokenB: Direcciones de los tokens.
// Retorno:
// price: Precio de tokenA en términos de tokenB.

    function getPrice(address _token) external view returns (uint256) {
        require(_token == address(tokenA) || _token == address(tokenB), "Invalid token");

        return _token == address(tokenA)
            ? (tokenB.balanceOf(address(this)) * 1e18) / tokenA.balanceOf(address(this))
            : (tokenA.balanceOf(address(this)) * 1e18) / tokenB.balanceOf(address(this));
    }

// 5️⃣Calcular Cantidad a Recibir (getAmountOut)
// Descripción: Función para calcular cuántos tokens se recibirán al intercambiar.
// Interfaz: function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
// Tareas:
// Calcular y retornar cantidad a recibir.
// Parámetros:
// amountIn: Cantidad de tokens de entrada.
// reserveIn, reserveOut: Reservas actuales en el contrato.
// Retorno:
// amountOut: Cantidad de tokens a recibir.

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut) {
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }
}
