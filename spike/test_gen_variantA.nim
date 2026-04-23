import nimfoot_auto_gen_variants, common

let r1 = targetGeneric(2, 3)
let r2 = targetGeneric[int](10, 20)

echo "variantA targetGeneric(2,3)=", r1, " [int](10,20)=", r2
echo "rewriteCountGen: ", rewriteCountGen
