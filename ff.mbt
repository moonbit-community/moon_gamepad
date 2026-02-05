///|
suberror FfError {
  NotSupported
}

///|
pub struct Effect {
  _id : Int
}

///|
pub struct EffectBuilder {
  mut _dummy : Int
}

///|
pub fn EffectBuilder::new() -> EffectBuilder {
  { _dummy: 0 }
}

///|
pub fn EffectBuilder::finish(
  self : EffectBuilder,
  _gilrs : Gilrs,
) -> Effect raise FfError {
  raise FfError::NotSupported
}

///|
pub fn Effect::play(self : Effect) -> Unit raise FfError {
  raise FfError::NotSupported
}

///|
pub fn Effect::stop(self : Effect) -> Unit raise FfError {
  raise FfError::NotSupported
}
