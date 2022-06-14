// build 폴더의 Migrations.js 파일을 가져옴
const Migrations = artifacts.require('Migrations');

module.exports = function (deployer) {
  deployer.deploy(Migrations);
};
