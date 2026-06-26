# Zuivere Python referentie voor Edwards25519 extended-coords puntrekenkunde.
# Dient als oracle voor de C64-module. Coords: (X,Y,Z,T) met x=X/Z, y=Y/Z, T=XY/Z.
p = 2**255 - 19
d = (-121665 * pow(121666, p-2, p)) % p
a = (-1) % p   # a = -1 voor twisted edwards van ed25519

# basispunt B
By = (4 * pow(5, p-2, p)) % p
# Bx via curve: a x^2 + y^2 = 1 + d x^2 y^2 -> recover x
def recover_x(y, sign):
    # x^2 = (y^2 - 1) / (d y^2 - a)
    y2 = y*y % p
    num = (y2 - 1) % p
    den = (d*y2 - a) % p
    x2 = num * pow(den, p-2, p) % p
    x = pow(x2, (p+3)//8, p)
    if (x*x - x2) % p != 0:
        x = x * pow(2, (p-1)//4, p) % p
    if x % 2 != sign:
        x = (p - x) % p
    return x
Bx = recover_x(By, 0)
B = (Bx, By, 1, Bx*By % p)

def point_add(P, Q):
    # HWCD extended, a=-1 (add-2008-hwcd-3)
    X1,Y1,Z1,T1 = P
    X2,Y2,Z2,T2 = Q
    A = (Y1 - X1) * (Y2 - X2) % p
    Bv= (Y1 + X1) * (Y2 + X2) % p
    C = T1 * 2 * d * T2 % p
    Dv= Z1 * 2 * Z2 % p
    E = Bv - A
    F = Dv - C
    G = Dv + C
    H = Bv + A
    X3 = E*F % p
    Y3 = G*H % p
    T3 = E*H % p
    Z3 = F*G % p
    return (X3,Y3,Z3,T3)

def point_dbl(P):
    # dbl-2008-hwcd, a=-1
    X1,Y1,Z1,T1 = P
    A = X1*X1 % p
    Bv= Y1*Y1 % p
    C = 2*Z1*Z1 % p
    Dv= (-A) % p          # a*A met a=-1
    E = ((X1+Y1)*(X1+Y1) - A - Bv) % p
    G = Dv + Bv
    F = G - C
    H = Dv - Bv
    X3 = E*F % p
    Y3 = G*H % p
    T3 = E*H % p
    Z3 = F*G % p
    return (X3,Y3,Z3,T3)

def scalar_mul(k, P):
    # Montgomery-ladder-vrij: simpele double-and-add, MSB->LSB
    R = (0, 1, 1, 0)   # neutral element (identity): (0,1,1,0)
    for i in reversed(range(256)):
        R = point_dbl(R)
        if (k >> i) & 1:
            R = point_add(R, P)
    return R

def to_affine(P):
    X,Y,Z,T = P
    zi = pow(Z, p-2, p)
    return (X*zi % p, Y*zi % p)

if __name__ == "__main__":
    # sanity: 1*B = B
    assert to_affine(scalar_mul(1, B)) == (Bx, By)
    # 2*B via dbl == add(B,B)
    assert to_affine(point_dbl(B)) == to_affine(point_add(B,B))
    print("d =", hex(d))
    print("Bx=", hex(Bx))
    print("By=", hex(By))
    print("ref_ed OK")
