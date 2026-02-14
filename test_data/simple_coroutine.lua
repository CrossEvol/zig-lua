-- Simple coroutine test
local co = coroutine.create(function ()
  print("co-body 1")
  coroutine.yield()
  print("co-body 2")
end)

print("main 1")
coroutine.resume(co)
print("main 2")
coroutine.resume(co)
print("main 3")
