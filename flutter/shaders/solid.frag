#version 450
layout(location = 1) in vec4 tint;
layout(location = 0) out vec4 fragment;
void main() {
  fragment = vec4(tint.rgb * tint.a, tint.a);
}
