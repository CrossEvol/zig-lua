t = {a = 1, b = 2, c = 3}
for k, v in pairs(t) do
  print(k, v)
end

-- a       1
-- b       2
-- c       3


t = {"a", "b", "c"}
for k, v in ipairs(t) do
  print(k, v)
end

-- 1       a
-- 2       b
-- 3       c
