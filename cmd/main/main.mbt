///|
async fn main {
  let args = @env.args()
  @gmkfs.run(args[1:])
}
