export function isMobileDevice() {
  const uaDataMobile = navigator.userAgentData?.mobile
  if (typeof uaDataMobile === "boolean") return uaDataMobile
  return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent)
}
