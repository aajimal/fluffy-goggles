group "default" {
  targets = ["omgwtfbbq", "hello", "goodbye", "alright"]
}

variable "REPO" {
  default = "ghcr.io/astriaorg"
}

variable "TAG" {
  default = "latest"
}

variable "SHA_TAG"   {
  default = "sha-undefined"
}
variable "VERSION_SHA_TAG" {
  default = "v0.0.0-sha-undefined"
}

target "omgwtfbbq" {
  context = "."
  dockerfile = "Dockerfile"
  tags = [
    "${REPO}/omgwtfbbq:${TAG}",
    "${REPO}/omgwtfbbq:${SHA_TAG}",
    "${REPO}/omgwtfbbq:${VERSION_SHA_TAG}"
  ]
}

target "hello" {
  inherits = ["omgwtfbbq"]
  tags = [
    "${REPO}/hello:${TAG}",
    "${REPO}/hello:${SHA_TAG}",
    "${REPO}/hello:${VERSION_SHA_TAG}"
  ]
}

target "goodbye" {
  inherits = ["omgwtfbbq"]
  tags = [
    "${REPO}/goodbye:${TAG}",
    "${REPO}/goodbye:${SHA_TAG}",
    "${REPO}/goodbye:${VERSION_SHA_TAG}"
  ]
}

target "alright" {
  inherits = ["omgwtfbbq"]
  tags = [
    "${REPO}/alright:${TAG}",
    "${REPO}/alright:${SHA_TAG}",
    "${REPO}/alright:${VERSION_SHA_TAG}"
  ]
}
