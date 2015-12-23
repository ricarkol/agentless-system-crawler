#!/bin/bash

cat > /tmp/meta << EOF
{"random_seed": "Ea1RkC0KDy7awjj/RdK4sbLnDvOtn6Py/1KJR/4+rBFmC6WIFUmA6tM3duu4ikXSq+tsW2ByPxUMlUZgGRX+MSfszgMjeT7zQCm15K5fbZ1SOEviyyI5ouNeQBzhrTGqWiIRkgGfwVAbcJG53tS9j+QPEYow1GiVbDm611khqdHgwY5SU0lHwPE/nMPa2+WP2oAhW9xYu87OXoAmzPf/SNnpWOfLKc6x/jnE07xC1XYAWQvfOWjrg1Ay4qlCE+IGqCv0MLofsUswokGUdCQ+xoPltu/BvKn+F5XXxDGhyW5Et7kF3Q7q50ZpWGt5DYi24OUKyqgvWPRsnbNP+OEJIBMBwLO8DqLEoAyn+qAQNdHDA7hGdUG6oVTW4sKCnmR962ixAnU1LmxqCuxTwaG04ILMVHoLWRyqJ5GMAXNKVzm8NhxsOfjGBHGiSgpOkTp8xisSXQ3qBIOcgbOdY1CkFEW55TaQxb5GJPGFk7ri4+7SGKYdx3PiV7B9fgGvUkfCRZ+r683Pef68GL2t++k+jzicqGGanRzyaDlUNuzVR+SUf1WjBXJpAMPc3lFsvjTSDwkgKp73Tu63iDSmRtD9KjOORVbeGkFPxFxcjCKdcQPoJn0BB+wAcfDmP/qPT+RWmcG5FLbyC1GfUtH587N6qX1aKzbICXtBtgWZ02gvW98=", "uuid": "<UUID>", "availability_zone": "nova", "hostname": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b.novalocal", "launch_index": 0, "meta": {"Cmd_0": "echo \"Hello world\"", "tagseparator": "_", "sgroup_name": "lindj_group1", "logging_password": "VSKHimqp69Nk", "Cmd_1": "/bin/bash", "tenant_id": "f75ec4e7-eb9d-463a-a90f-f8226572fbcc", "testvar1": "testvalue1", "sgroup_id": "dd28638d-7c10-4e26-9059-6e0baba7f64d", "test2": "supercoolvar2", "logstash_target": "logmet.stage1.opvis.bluemix.net:9091", "tagformat": "tenant_id group_id uuid", "metrics_target": "logmet.stage1.opvis.bluemix.net:9095", "group_id": "dd28638d-7c10-4e26-9059-6e0baba7f64d"}, "name": "li-l6o5-3mvyy3m5ug3l-r2wazwiucexe-server-52l5wrw5277b"}
EOF

sed -i s"/<UUID>/`uuid`/" /tmp/meta
mv /tmp/meta /openstack/nova/metadata/${1}.json
