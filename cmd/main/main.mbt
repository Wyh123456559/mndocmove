///|
async fn main {
  finish(@cli.run(@env.args()[1:].to_owned()))
}

///|
#cfg(target="native")
extern "C" fn finish(code : Int32) = "exit"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn finish(code : Int32) = "moonbitlang/async" "runtime/exit"
