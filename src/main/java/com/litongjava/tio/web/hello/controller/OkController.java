package com.litongjava.tio.web.hello.controller;

import nexus.io.annotation.RequestPath;
import nexus.io.model.body.RespBodyVo;

@RequestPath
public class OkController {

  @RequestPath("/ok")
  public RespBodyVo ok() {
    return RespBodyVo.ok();
  }
}
