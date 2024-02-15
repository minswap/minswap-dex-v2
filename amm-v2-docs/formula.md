# Minswap AMM V2 Formula

Minswap AMM V2 is using Constant Product formula ($x * y = k$). Any kind of action interacting with Liquidity Pool have to follow the constraint. 

Before we go to details, here are some definitions:
- $x_{0}$ and $y_{0}$ are reserves of Asset A and Asset B in Liquiity Pool
- $L$ is Circulating LP Token of Liquidity Pool (Total Liquidity)
- $\Delta x$ and $\Delta y$ are the changes of Asset A and Asset B
- $\Delta L$ is the changes of Circulating LP Token
- $f = \frac{f_{n}}{f_{d}}$ is Trading Fee of Liquidity Pool
- $fs = \frac{fs_{n}}{fs_{d}}$ is Protocol Fee of Liquidity Pool (aka Fee Sharing, Admin Fee or Profit Sharing...)

## AMM has 2 main formula:
### 1. When the price changes (Swap)
When a Token is swapped, Swap Fee is deducted from the input amount ($\Delta x$) 
$$ k = x_{0} * y_{0}$$
$$ k = (x_{0} + (1 - f) * \Delta x) * (y_{0} - \Delta y)$$

### 2. When the price is not changes (Add or Remove Liquidity)
$$\frac{\Delta x}{x_{0}} = \frac{\Delta y}{y_{0}}$$

## Functional formula
### 1. Swap Exact In
$$ k = x_{0} * y_{0} = (x_{0} + (1 - f) * \Delta x) * (y_{0} - \Delta y)$$
$$ k = x_{0} * y_{0} = x_{0} * y_{0} + (1 -f) * \Delta x * y_{0} - (x_{0} + (1 -f ) * \Delta x) * \Delta y$$
$$ \Delta y = \frac{(1 - f) * \Delta x * y_{0}}{x_{0} + (1 - f) * \Delta x}$$
$$ \Delta y = \frac{(1 - \frac{f_{n}}{f_{d}}) * \Delta x * y_{0}}{x_{0} + (1 - \frac{f_{n}}{f_{d}}) * \Delta x}$$
$$ \Delta y = \frac{(f_{d} - f_{n}) * \Delta x * y_{0}}{x_{0} * f_{d} + (f_{d} - f_{n}) * \Delta x}$$

### 2. Swap Exact Out
The calculation formula is the same with Swap Exact Out. but the result is $\Delta x$
$$\Delta x = \frac{x_{0} * \Delta y * f_{d}}{(f_{d} - f_{n}) * (y_{0} - \Delta y)} + 1$$

### 3. Deposit
On the V2, we allow users to deposit with any amount A & B, so there are two cases can happen:
- $\frac{\Delta x}{x_{0}} = \frac{\Delta y}{y_{0}} \Rightarrow \Delta L = \frac{\Delta x}{x_{0}} * L$
- $\frac{\Delta x}{x_{0}} \#  \frac{\Delta y}{y_{0}}$:
  - $\frac{\Delta x}{x_{0}} >  \frac{\Delta y}{y_{0}}$: We need to Swap a part of X to Y
  - $\frac{\Delta x}{x_{0}} <  \frac{\Delta y}{y_{0}}$: We need to Swap a part of Y to X

Here are the math for swap a part of X to Y:  
$$\frac{\Delta x - swap_{x}}{x_{0} + swap_{x}} = \frac{\Delta y + receive_{y}}{y_{0} - receive_{y}}$$
$$ x_{0} * y_{0} = (x_{0} + (1 - f) * swap_{x}) * (y_{0} - receive_{b})$$
Combine 2 equations above, we have
$$receive_{y} = \frac{(1 - f) * swap_{x} * y_{0}}{x_{0} + (1 - f) * swap_{x}}$$
$$\frac{\Delta x - swap_{x}}{x_{0} + swap_{x}} = \frac{\Delta y + \frac{(1 - f) * swap_{x} * y_{0}}{x_{0} + (1 - f) * swap_{x}}}{y_{0} - \frac{(1 - f) * swap_{x} * y_{0}}{x_{0} + (1 - f) * swap_{x}}}$$

$$(1 - f) * (y_{0} + \Delta y) * swap_{x}^{2} + (2 - f) * (y_{0} + \Delta y) * x_{0} * swap_{x} + (x_{0}^{2} * \Delta y - x_{0} * y_{0} * \Delta x) = 0$$
let $A = (1 - f) * (y_{0} + \Delta y)$, $B = (2 - f) * (y_{0} + \Delta y) * x_{0}$, $C = (x_{0}^{2} * \Delta y - x_{0} * y_{0} * \Delta x)$

$$swap_{x} = \left\lfloor \frac{-B + \sqrt{B^{2} - 4 * A * C}}{2 * A} \right\rfloor$$
$$= \left\lfloor \frac{\sqrt{((2 - f) * (y_{0} + \Delta y) * x_{0})^{2} - 4 * (1 - f) * (y_{0} + \Delta y) * (x_{0}^{2} * \Delta y - x_{0} * y_{0} * \Delta x)} - (2 - f) * (y_{0} + \Delta y) * x_{0}}{2 * (1 - f) * (y_{0} + \Delta y)} \right\rfloor$$

let $X = (y_{0} + \Delta y) * x_{0}$, $Y = 4 * (y_{0} + \Delta y) * (x_{0}^{2} * \Delta y - x_{0} * y_{0} * \Delta x)$, $Z = 2 * (y_{0} + \Delta y)$
$$swap_{x} = \left\lfloor \frac{\sqrt{((2 - f) * X)^{2} - (1 - f) * Y} - (2 - f) * X}{(1 - f) * Z} \right\rfloor$$
$$= \left\lfloor \frac{\sqrt{((2 * f_{d} - f_{n}) * X)^{2} - f_{d} * (f_{d} - f_{n}) * Y} - (2 * f_{d} - f_{n}) * X}{(f_{d} - f_{n}) * Z} \right\rfloor $$

The LP Token users receive is:
$$\Delta L = \frac{\Delta y + receive_{y}}{y_{0} - receive_{y}} * L$$

### 4. Withdraw
$$\Delta x = \frac{\Delta L}{L} * x_{0}$$
$$\Delta y = \frac{\Delta L}{L} * y_{0}$$

### 5. Zap Out
After Withdraw, users have 
$$\Delta x = \frac{\Delta L}{L} * x_{0}$$
$$\Delta y = \frac{\Delta L}{L} * y_{0}$$

In case users want to zap out to Asset B, $\Delta x$ will be swapped, then total amount users receive is
$$Out = \Delta y + \frac{(f_{d} - f_{n}) * \Delta x * y_{0}}{x_{0} * f_{d} + (f_{d} - f_{n}) * \Delta x}$$

### 6. Withdraw Imbalance

Users want to withdraw with a ratio $A/B$. 

We have the basic withdrawal formulas:

$$\Delta x = \frac{\Delta L}{L} * x_{0}$$
$$\Delta y = \frac{\Delta L}{L} * y_{0}$$

Suppose we need to swap some in $\Delta x$ to get $\frac{\Delta x'}{\Delta y'} = \frac{A}{B}$.

So we have the formula:
$$\frac{\Delta x - swap_{x}}{\Delta y + receive_{y}} =\frac{A}{B} (1)$$


$$ receive_{y} = \frac{(f_{d} - f_{n}) * swap_{x} * y_{0}}{x_{0} * f_{d} + (f_{d} - f_{n}) * swap_{x}}(2)$$

(With $x_{0}$ and $y_{0}$ being $x$ and $y$ after withdrawal, $swap_{x}$ is the amount need to be swapped to adapt the ratio $A/B$ that users expect).

Combination of formula (1) and (2), we have:

$$a * swap_{x} ^ 2 + b * swap_{x} + c = 0$$
where 
$$a = (f_{d} - f_{n}) * B$$
$$b = A*(f_{d} - f_{n})*(y_{0}+\Delta y) + B *(f_{d} * x_{0} - (f_{d} - f_{n})*\Delta x)$$
$$ c =f_{d} * x_{0} *(A * \Delta y - B * \Delta x) $$

### 7. Partial Swap
Allow users swap only if price is exactly matched.

In case users want to swap with price $A/B$
We have 2 formulas: 
$$\frac{\Delta x}{\Delta y} = \frac{A}{B}  (1)$$
$$ \Delta y = \frac{(f_{d} - f_{n}) * \Delta x * y_{0}}{x_{0} * f_{d} + (f_{d} - f_{n}) * \Delta x} (2)$$
We can calculate $\Delta x$: 
$$\Delta x = \frac{A * (f_{d} - f_{n}) * y_{0} - B * f_{d} * x_{0}}{(f_{d} - f_{n}) * B}$$
where $\Delta x$ is the maximum amount can be swapped to adapt $A/B$ ratio