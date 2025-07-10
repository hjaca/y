// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

// Importamos la interfaz del LiquidityToken
interface ILiquidityToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @title SimpleSwap
 * @dev Implementación de un AMM (Automated Market Maker) simple
 * que replica la funcionalidad básica de Uniswap V2
 * Usa un token LP externo para representar la liquidez
 */
contract SimpleSwap  {
    using Math for uint256;

    // Estructura para almacenar información de cada pool
    struct Pool {
        address tokenA;
        address tokenB;
        uint256 reserveA;
        uint256 reserveB;
        bool exists; // Flag para verificar si el pool existe
    }

    // ✅ NUEVAS ESTRUCTURAS PARA RESOLVER STACK TOO DEEP
    struct SwapData {
        address tokenIn;
        address tokenOut;
        bytes32 poolId;
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amountOut;
    }

    struct RemoveLiquidityData {
        bytes32 poolId;
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalSupply;
        uint256 amountA;
        uint256 amountB;
    }

    struct AddLiquidityData {
        bytes32 poolId;
        uint256 totalSupply;
        uint256 reserveA;
        uint256 reserveB;
        uint256 amountA;
        uint256 amountB;
        uint256 liquidity;
    }

    // Mapeo de pools: keccak256(tokenA, tokenB) => Pool
    mapping(bytes32 => Pool) public pools;
    
    // Token de liquidez que se mintea/quema para representar participaciones
    ILiquidityToken public immutable liquidityToken;

    // Eventos
    event LiquidityAdded(
        address indexed user,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );

    event LiquidityRemoved(
        address indexed user,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );

    event Swap(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event PoolCreated(
        address indexed tokenA,
        address indexed tokenB,
        bytes32 indexed poolId
    );

    /**
     * @dev Constructor que establece el token de liquidez
     * @param _liquidityToken Dirección del contrato LiquidityToken
     */
    constructor(address _liquidityToken) {
        require(_liquidityToken != address(0), "SimpleSwap: ZERO_ADDRESS");
        liquidityToken = ILiquidityToken(_liquidityToken);
    }

    /**
     * @dev Modifier para validar deadline de transacciones
     */
    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "SimpleSwap: EXPIRED");
        _;
    }

    /**
     * @dev Obtiene el ID único del pool para dos tokens
     */
    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        // Ordenamos los tokens para que el pool sea el mismo independientemente del orden
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1));
    }

    /**
     * @dev Ordena los tokens para mantener consistencia
     */
    function sortTokens(address tokenA, address tokenB) 
        internal 
        pure 
        returns (address token0, address token1) 
    {
        require(tokenA != tokenB, "SimpleSwap: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "SimpleSwap: ZERO_ADDRESS");
    }

    /**
     * @dev Obtiene las reservas ordenadas de un pool
     */
    function getReserves(address tokenA, address tokenB) 
        public 
        view 
        returns (uint256 reserveA, uint256 reserveB) 
    {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        
        require(pool.exists, "SimpleSwap: POOL_NOT_EXISTS");
        
        if (pool.tokenA == tokenA) {
            reserveA = pool.reserveA;
            reserveB = pool.reserveB;
        } else {
            reserveA = pool.reserveB;
            reserveB = pool.reserveA;
        }
    }

    /**
     * @dev Crea un nuevo pool si no existe
     */
    function _createPool(address tokenA, address tokenB) internal returns (bytes32 poolId) {
        poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        
        if (!pool.exists) {
            (address token0, address token1) = sortTokens(tokenA, tokenB);
            pool.tokenA = token0;
            pool.tokenB = token1;
            pool.exists = true;
            
            emit PoolCreated(token0, token1, poolId);
        }
    }

    /**
     * @dev 1️⃣ Agregar Liquidez - VERSIÓN REFACTORIZADA
     * Permite a los usuarios agregar liquidez a un pool
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) 
        external 
        checkDeadline(deadline)
//        nonReentrant
        returns (uint256 amountA, uint256 amountB, uint256 liquidity) 
    {
        require(tokenA != tokenB, "SimpleSwap: IDENTICAL_ADDRESSES");
        require(to != address(0), "SimpleSwap: ZERO_ADDRESS");

        AddLiquidityData memory data;
        data.poolId = _createPool(tokenA, tokenB);
        data.totalSupply = liquidityToken.totalSupply();
        
        if (data.totalSupply == 0) {
            // Primer depósito de liquidez
            (data.amountA, data.amountB, data.liquidity) = _handleFirstLiquidity(
                amountADesired, 
                amountBDesired
            );
        } else {
            // Pool ya tiene liquidez, mantener proporción
            (data.amountA, data.amountB, data.liquidity) = _handleSubsequentLiquidity(
                tokenA,
                tokenB,
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                data.totalSupply
            );
        }

        require(data.liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");

        // Ejecutar transferencias y actualizaciones
        _executeAddLiquidity(tokenA, tokenB, data, to);

        return (data.amountA, data.amountB, data.liquidity);
    }

    function _handleFirstLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired
    ) internal pure returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = Math.sqrt(amountA * amountB);
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");
    }

    function _handleSubsequentLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 totalSupply
    ) internal view returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);
        
        uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
        
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, "SimpleSwap: INSUFFICIENT_B_AMOUNT");
            amountA = amountADesired;
            amountB = amountBOptimal;
        } else {
            uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
            require(amountAOptimal <= amountADesired && amountAOptimal >= amountAMin, 
                    "SimpleSwap: INSUFFICIENT_A_AMOUNT");
            amountA = amountAOptimal;
            amountB = amountBDesired;
        }

        // Calcular tokens LP a emitir
        liquidity = Math.min(
            (amountA * totalSupply) / reserveA,
            (amountB * totalSupply) / reserveB
        );
    }

    function _executeAddLiquidity(
        address tokenA,
        address tokenB,
        AddLiquidityData memory data,
        address to
    ) internal {
        Pool storage pool = pools[data.poolId];

        // Transferir tokens del usuario al contrato
        IERC20(tokenA).transferFrom(msg.sender, address(this), data.amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), data.amountB);

        // Actualizar reservas
        if (pool.tokenA == tokenA) {
            pool.reserveA += data.amountA;
            pool.reserveB += data.amountB;
        } else {
            pool.reserveA += data.amountB;
            pool.reserveB += data.amountA;
        }
        
        // Mintear tokens LP al usuario
        liquidityToken.mint(to, data.liquidity);

        emit LiquidityAdded(to, tokenA, tokenB, data.amountA, data.amountB, data.liquidity);
    }

    /**
     * @dev 2️⃣ Remover Liquidez - VERSIÓN REFACTORIZADA
     * Permite a los usuarios retirar liquidez de un pool
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) 
        external 
        checkDeadline(deadline)
//        nonReentrant
        returns (uint256 amountA, uint256 amountB) 
    {
        require(to != address(0), "SimpleSwap: ZERO_ADDRESS");
        
        RemoveLiquidityData memory data;
        data.poolId = getPoolId(tokenA, tokenB);
        
        Pool storage pool = pools[data.poolId];
        require(pool.exists, "SimpleSwap: POOL_NOT_EXISTS");
        require(liquidityToken.balanceOf(msg.sender) >= liquidity, "SimpleSwap: INSUFFICIENT_LIQUIDITY");

        (data.reserveA, data.reserveB) = getReserves(tokenA, tokenB);
        data.totalSupply = liquidityToken.totalSupply();

        // Calcular cantidad de tokens a devolver
        data.amountA = (liquidity * data.reserveA) / data.totalSupply;
        data.amountB = (liquidity * data.reserveB) / data.totalSupply;

        require(data.amountA >= amountAMin, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
        require(data.amountB >= amountBMin, "SimpleSwap: INSUFFICIENT_B_AMOUNT");

        // Ejecutar remoción de liquidez
        _executeRemoveLiquidity(tokenA, tokenB, data, pool, liquidity, to);

        return (data.amountA, data.amountB);
    }

    function _executeRemoveLiquidity(
        address tokenA,
        address tokenB,
        RemoveLiquidityData memory data,
        Pool storage pool,
        uint256 liquidity,
        address to
    ) internal {
        // Quemar tokens LP
        liquidityToken.burn(msg.sender, liquidity);

        // Actualizar reservas
        if (pool.tokenA == tokenA) {
            pool.reserveA -= data.amountA;
            pool.reserveB -= data.amountB;
        } else {
            pool.reserveA -= data.amountB;
            pool.reserveB -= data.amountA;
        }

        // Transferir tokens al usuario
        IERC20(tokenA).transfer(to, data.amountA);
        IERC20(tokenB).transfer(to, data.amountB);

        emit LiquidityRemoved(to, tokenA, tokenB, data.amountA, data.amountB, liquidity);
    }

    /**
     * @dev 3️⃣ Intercambiar Tokens - 
     * Intercambia una cantidad exacta de tokens por otros
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) 
        external 
        checkDeadline(deadline)
//        nonReentrant
        returns (uint256[] memory amounts) 
    {
        require(path.length == 2, "SimpleSwap: INVALID_PATH");
        require(to != address(0), "SimpleSwap: ZERO_ADDRESS");

        SwapData memory swapData;
        swapData.tokenIn = path[0];
        swapData.tokenOut = path[1];
        
        swapData.poolId = getPoolId(swapData.tokenIn, swapData.tokenOut);
        Pool storage pool = pools[swapData.poolId];
        require(pool.exists, "SimpleSwap: POOL_NOT_EXISTS");

        (swapData.reserveIn, swapData.reserveOut) = getReserves(swapData.tokenIn, swapData.tokenOut);
        
        swapData.amountOut = getAmountOut(amountIn, swapData.reserveIn, swapData.reserveOut);
        require(swapData.amountOut >= amountOutMin, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = swapData.amountOut;

        // Ejecutar el swap
        _executeSwap(swapData, pool, amountIn, to);

        emit Swap(msg.sender, swapData.tokenIn, swapData.tokenOut, amountIn, swapData.amountOut);
    }

    /**
     * @dev Función interna para ejecutar el swap
     */
    function _executeSwap(
        SwapData memory swapData,
        Pool storage pool,
        uint256 amountIn,
        address to
    ) internal {
        // Transferir token de entrada del usuario
        IERC20(swapData.tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Actualizar reservas
        if (pool.tokenA == swapData.tokenIn) {
            pool.reserveA += amountIn;
            pool.reserveB -= swapData.amountOut;
        } else {
            pool.reserveA -= swapData.amountOut;
            pool.reserveB += amountIn;
        }

        // Transferir token de salida al usuario
        IERC20(swapData.tokenOut).transfer(to, swapData.amountOut);
    }

    /**
     * @dev 4️⃣ Obtener Precio
     * Retorna el precio de tokenA en términos de tokenB
     */
    function getPrice(address tokenA, address tokenB) 
        external 
        view 
        returns (uint256 price) 
    {
        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);
        require(reserveA > 0 && reserveB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        
        // Precio = reserveB / reserveA (con 18 decimales de precisión)
        price = (reserveB * 1e18) / reserveA;
    }

    /**
     * @dev 5️⃣ Calcular Cantidad a Recibir
     * Calcula cuántos tokens se recibirán en un swap
     * Usa la fórmula de producto constante: x * y = k
     */
    function getAmountOut(
        uint256 amountIn, 
        uint256 reserveIn, 
        uint256 reserveOut
    ) 
        public 
        pure 
        returns (uint256 amountOut) 
    {
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");

        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    /**
     * @dev Obtener balance de liquidez de un usuario
     */
    function getLiquidityBalance(address user) 
        external 
        view 
        returns (uint256) 
    {
        return liquidityToken.balanceOf(user);
    }

    /**
     * @dev Obtener información completa de un pool
     */
    function getPoolInfo(address tokenA, address tokenB) 
        external 
        view 
        returns (
            address token0,
            address token1,
            uint256 reserve0,
            uint256 reserve1,
            uint256 totalSupply,
            bool exists
        ) 
    {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        
        token0 = pool.tokenA;
        token1 = pool.tokenB;
        reserve0 = pool.reserveA;
        reserve1 = pool.reserveB;
        totalSupply = liquidityToken.totalSupply();
        exists = pool.exists;
    }

    /**
     * @dev Verifica si un pool existe
     */
    function poolExists(address tokenA, address tokenB) external view returns (bool) {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        return pools[poolId].exists;
    }
}
